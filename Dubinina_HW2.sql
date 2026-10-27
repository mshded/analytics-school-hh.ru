SET search_path TO hh_school;

-- Блок А. Качество и подготовка данных
-- ЗАДАНИЕ 1

WITH calls_info AS (
    SELECT
        c.call_id,
        c.response_id,
        c.employer_id,
        c.vacancy_id,
        c.call_duration,
        c.status,
        c.call_at,
        r.vacancy_id AS response_vacancy_id,
        r.created_at AS response_created_at,
        v.employer_id AS vacancy_employer_id,
        v.closed_at
    FROM calls AS c
    LEFT JOIN responses AS r
        ON r.response_id = c.response_id
    LEFT JOIN vacancies AS v
        ON v.vacancy_id = r.vacancy_id
),
 
messages_info AS (
    SELECT
        m.message_id,
        m.response_id,
        m.employer_id,
        m.vacancy_id,
        m.sent_at,
        r.vacancy_id AS response_vacancy_id,
        r.created_at AS response_created_at,
        v.employer_id AS vacancy_employer_id,
        v.closed_at
    FROM messages AS m
    JOIN responses AS r
        ON r.response_id = m.response_id
    LEFT JOIN vacancies AS v
        ON v.vacancy_id = r.vacancy_id
),
 
duration_p99 AS (
    SELECT
        percentile_cont(0.99) WITHIN GROUP (
            ORDER BY call_duration
        ) AS p99
    FROM calls
    WHERE status = 'successful'
),
 
problems AS (
    SELECT
        'call_without_response'::text AS problem_type,
        'call'::text AS event_type,
        call_id AS event_id,
        'звонок был, но его нельзя связать с конкретным откликом'::text
            AS problem_comment
    FROM calls_info
    WHERE response_id IS NULL
 
    UNION ALL
 
    SELECT
        'call_wrong_vacancy',
        'call',
        call_id,
        'звонок был, но непонятно, к какой вакансии его относить'
    FROM calls_info
    WHERE response_id IS NOT NULL
      AND vacancy_id <> response_vacancy_id
 
    UNION ALL
 
    SELECT
        'message_wrong_vacancy',
        'message',
        message_id,
        'сообщение было, но непонятно, к какой вакансии его относить'
    FROM messages_info
    WHERE vacancy_id <> response_vacancy_id
 
    UNION ALL
 
    SELECT
        'call_wrong_employer',
        'call',
        call_id,
        'на факт звонка не влияет, но работодатель указан неправильно'
    FROM calls_info
    WHERE response_id IS NOT NULL
      AND employer_id <> vacancy_employer_id
 
    UNION ALL
 
    SELECT
        'message_wrong_employer',
        'message',
        message_id,
        'на факт сообщения не влияет, но работодатель указан неправильно'
    FROM messages_info
    WHERE employer_id <> vacancy_employer_id
 
    UNION ALL
 
    SELECT
        'call_before_response',
        'call',
        call_id,
        'звонок был раньше отклика, поэтому связь с откликом выглядит некорректно'
    FROM calls_info
    WHERE response_id IS NOT NULL
      AND call_at < response_created_at
 
    UNION ALL
 
    SELECT
        'message_before_response',
        'message',
        message_id,
        'сообщение было раньше отклика, поэтому связь с откликом выглядит некорректно'
    FROM messages_info
    WHERE sent_at < response_created_at
 
    UNION ALL
 
    SELECT
        'call_after_vacancy_closure',
        'call',
        call_id,
        'на факт звонка не влияет, общение могло продолжиться после закрытия вакансии'
    FROM calls_info
    WHERE response_id IS NOT NULL
      AND closed_at IS NOT NULL
      AND call_at > closed_at
 
    UNION ALL
 
    SELECT
        'message_after_vacancy_closure',
        'message',
        message_id,
        'на факт сообщения не влияет, общение могло продолжиться после закрытия вакансии'
    FROM messages_info
    WHERE closed_at IS NOT NULL
      AND sent_at > closed_at
 
    UNION ALL
 
    SELECT
        'call_duration_above_p99',
        'call',
        c.call_id,
        'на факт звонка не влияет, необычное значение длительности'
    FROM calls_info AS c
    CROSS JOIN duration_p99 AS p
    WHERE c.status = 'successful'
      AND c.call_duration > p.p99
)
 
SELECT
    problem_type,
    COUNT(*) AS problem_count,
    array_agg(event_id ORDER BY event_id)
        FILTER (WHERE event_type = 'call') AS call_ids,
    array_agg(event_id ORDER BY event_id)
        FILTER (WHERE event_type = 'message') AS message_ids,
    problem_comment
FROM problems
GROUP BY
    problem_type,
    problem_comment
ORDER BY problem_type;

/* 
 
Вывод:

в результате проверки было найдено 4 типа проблем:
 
8 звонков не связаны с откликом, так как у них не заполнен response_id.
сам звонок может быть реальным, но такие строки нельзя использовать
для расчёта коммуникаций по откликам.
 
10 звонков и 180 сообщений произошли после закрытия вакансии.
я не считаю это ошибкой, потому что работодатель и кандидат могли продолжить
общение после закрытия вакансии. такие события можно учитывать как факт
коммуникации, если мы не ограничены по времени.
 
у 2 успешных звонков с call_id 700159 и 700199 длительность выше
99-го перцентиля. это влияет на показатель длительности. это допустимые выбросы, а не ошибки, так как
это могут быть реальные долгие разговоры и поэтому при подсчете коммуникаций, я бы оставила данные
звонки. для оценки типичной длительности можно использовать медиану, так как она меньше зависит от выбросов, 
чем среднее. если нужна именно средняя длительность, я бы использовала среднее после удаления значений
выше 99-го перцентиля.

*/

WITH successful_calls AS (
    SELECT
        call_id,
        call_duration
    FROM calls
    WHERE status = 'successful'
),
stats AS (
    SELECT
        AVG(call_duration) AS avg_duration,
        percentile_cont(0.5) WITHIN GROUP (
            ORDER BY call_duration
        ) AS median_duration,
        percentile_cont(0.99) WITHIN GROUP (
            ORDER BY call_duration
        ) AS p99_duration
    FROM successful_calls
)
SELECT
    ROUND(s.avg_duration::numeric, 2) AS avg_duration,
    ROUND(s.median_duration::numeric, 2) AS median_duration,
    ROUND(s.p99_duration::numeric, 2) AS p99_duration,
    COUNT(*) FILTER (
        WHERE c.call_duration > s.p99_duration
    ) AS calls_above_p99,
    ROUND(
        AVG(c.call_duration) FILTER (
            WHERE c.call_duration <= s.p99_duration
        )::numeric,
        2
    ) AS avg_duration_without_above_p99
FROM successful_calls AS c
CROSS JOIN stats AS s
GROUP BY
    s.avg_duration,
    s.median_duration,
    s.p99_duration;

/*
Продолжение вывода:

значения длительности успешных звонков:
- средняя длительность -  467.28 сек
- медианная длительность - 438.00 сек
- 99-й перцентиль - 890.40 сек
- количество звонков выше 99-го перцентиля - 2
- средняя длительность без значений выше 99-го перцентиля -  462.49 сек
*/

-- Блок Б. История коммуникаций
-- ЗАДАНИЕ 2

WITH calls_prepared AS (
    SELECT
        c.response_id,
        c.employer_id,
        c.call_id AS event_id,
        c.call_at AS event_at,
        'call'::text AS event_type
    FROM calls AS c
    JOIN responses AS r
        ON r.response_id = c.response_id
    JOIN vacancies AS v
        ON v.vacancy_id = r.vacancy_id
    WHERE c.caller_role = 'employer'
      AND c.vacancy_id = r.vacancy_id
      AND c.employer_id = v.employer_id
      AND c.call_at >= r.created_at
      AND c.call_at < r.created_at + INTERVAL '7 days'
),
 
messages_prepared AS (
    SELECT
        m.response_id,
        m.employer_id,
        m.message_id AS event_id,
        m.sent_at AS event_at,
        'message'::text AS event_type
    FROM messages AS m
    JOIN responses AS r
        ON r.response_id = m.response_id
    JOIN vacancies AS v
        ON v.vacancy_id = r.vacancy_id
    WHERE m.sender_role = 'employer'
      AND m.vacancy_id = r.vacancy_id
      AND m.employer_id = v.employer_id
      AND m.sent_at >= r.created_at
      AND m.sent_at < r.created_at + INTERVAL '7 days'
),
 
communications AS (
    SELECT
        response_id,
        employer_id,
        event_id,
        event_at,
        event_type
    FROM calls_prepared
 
    UNION ALL
 
    SELECT
        response_id,
        employer_id,
        event_id,
        event_at,
        event_type
    FROM messages_prepared
)
 
SELECT
    COUNT(*) AS events_count,
    COUNT(DISTINCT response_id) AS responses_with_communication,
    COUNT(*) FILTER (
        WHERE event_type = 'call'
    ) AS calls_count,
    COUNT(*) FILTER (
        WHERE event_type = 'message'
    ) AS messages_count
FROM communications;
 
/*
Вывод:
 
в первые 7 дней после отклика работодатели совершили всего 1096 событий.
 
коммуникация со стороны работодателя была по 382 различным откликам.
 
из общего количества событий:
- звонков - 108
- сообщений - 988
 
в слой не вошли звонки без response_id, события с несовпадающей вакансией
или работодателем, а также события, которые произошли раньше отклика.
 
звонки с длительностью выше 99-го перцентиля я оставила в выборке, события после закрытия
вакансии также оставила, если они произошли в первые 7 дней после отклика,
так как общение с кандидатом могло продолжаться после закрытия вакансии.
*/

-- ЗАДАНИЕ 3

WITH calls_prepared AS (
    SELECT
        c.response_id,
        c.employer_id,
        c.call_id AS event_id,
        c.call_at AS event_at,
        'call'::text AS event_type
    FROM calls AS c
    JOIN responses AS r
        ON r.response_id = c.response_id
    JOIN vacancies AS v
        ON v.vacancy_id = r.vacancy_id
    WHERE c.caller_role = 'employer'
      AND c.vacancy_id = r.vacancy_id
      AND c.employer_id = v.employer_id
      AND c.call_at >= r.created_at
      AND c.call_at < r.created_at + INTERVAL '7 days'
),
 
messages_prepared AS (
    SELECT
        m.response_id,
        m.employer_id,
        m.message_id AS event_id,
        m.sent_at AS event_at,
        'message'::text AS event_type
    FROM messages AS m
    JOIN responses AS r
        ON r.response_id = m.response_id
    JOIN vacancies AS v
        ON v.vacancy_id = r.vacancy_id
    WHERE m.sender_role = 'employer'
      AND m.vacancy_id = r.vacancy_id
      AND m.employer_id = v.employer_id
      AND m.sent_at >= r.created_at
      AND m.sent_at < r.created_at + INTERVAL '7 days'
),
 
communications AS (
    SELECT
        response_id,
        employer_id,
        event_id,
        event_at,
        event_type
    FROM calls_prepared
 
    UNION ALL
 
    SELECT
        response_id,
        employer_id,
        event_id,
        event_at,
        event_type
    FROM messages_prepared
),
 
event_timeline AS (
    SELECT
        response_id,
        employer_id,
        event_id,
        event_at,
        event_type,
 
        ROW_NUMBER() OVER (
            PARTITION BY response_id
            ORDER BY event_at, event_type, event_id
        ) AS event_number,
 
        LAG(event_at) OVER (
            PARTITION BY response_id
            ORDER BY event_at, event_type, event_id
        ) AS previous_event_at,
 
        LEAD(event_type) OVER (
            PARTITION BY response_id
            ORDER BY event_at, event_type, event_id
        ) AS next_event_type,
 
        COUNT(*) OVER (
            PARTITION BY response_id
            ORDER BY event_at, event_type, event_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS communications_from_start,
 
        FIRST_VALUE(event_type) OVER (
            PARTITION BY response_id
            ORDER BY event_at, event_type, event_id
        ) AS first_event_type,
 
        FIRST_VALUE(event_type) OVER (
            PARTITION BY response_id
            ORDER BY event_at DESC, event_type DESC, event_id DESC
        ) AS last_event_type
    FROM communications
),
 
event_stats AS (
    SELECT
        response_id,
        COUNT(*) AS communications_count,
        COUNT(*) FILTER (
            WHERE event_type = 'call'
        ) AS calls_count,
        COUNT(*) FILTER (
            WHERE event_type = 'message'
        ) AS messages_count,
        MIN(event_at) AS first_event_at,
        MAX(first_event_type) AS first_event_type,
        MAX(event_type) FILTER (
            WHERE event_number = 2
        ) AS second_event_type,
        MAX(last_event_type) AS last_event_type,
        MAX(
            EXTRACT(
                EPOCH FROM (event_at - previous_event_at)
            ) / 3600.0
        ) AS max_interval_hours
    FROM event_timeline
    GROUP BY response_id
),
 
response_mart AS (
    SELECT
        r.response_id,
        v.employer_id,
        v.professional_role,
        r.status AS response_status,
        COALESCE(es.communications_count, 0) AS communications_count,
        COALESCE(es.calls_count, 0) AS calls_count,
        COALESCE(es.messages_count, 0) AS messages_count,
        es.first_event_at,
        es.first_event_type,
        es.second_event_type,
        es.last_event_type,
        EXTRACT(
            EPOCH FROM (es.first_event_at - r.created_at)
        ) / 3600.0 AS hours_to_first_event,
        es.max_interval_hours
    FROM responses AS r
    JOIN vacancies AS v
        ON v.vacancy_id = r.vacancy_id
    LEFT JOIN event_stats AS es
        ON es.response_id = r.response_id
)
 
SELECT
    COUNT(*) AS rows_count,
    COUNT(*) FILTER (
        WHERE communications_count > 0
    ) AS responses_with_communication,
    COUNT(*) FILTER (
        WHERE communications_count = 0
    ) AS responses_without_communication,
    COUNT(*) FILTER (
        WHERE first_event_type = 'message'
    ) AS responses_first_message,
    COUNT(*) FILTER (
        WHERE first_event_type = 'call'
    ) AS responses_first_call
FROM response_mart;
 
/*
Вывод:
 
- количество строк - 628
- количество откликов с коммуникацией 382
- количество откликов без коммуникации - 246
- количество откликов, где первой коммуникацией было сообщение - 314
- количество откликов, где первой коммуникацией был звонок - 68
*/

-- ЗАДАНИЕ 4

WITH calls_prepared AS (
    SELECT
        c.response_id,
        c.employer_id,
        c.call_id AS event_id,
        c.call_at AS event_at,
        'call'::text AS event_type
    FROM calls AS c
    JOIN responses AS r
        ON r.response_id = c.response_id
    JOIN vacancies AS v
        ON v.vacancy_id = r.vacancy_id
    WHERE c.caller_role = 'employer'
      AND c.vacancy_id = r.vacancy_id
      AND c.employer_id = v.employer_id
      AND c.call_at >= r.created_at
      AND c.call_at < r.created_at + INTERVAL '7 days'
),
 
messages_prepared AS (
    SELECT
        m.response_id,
        m.employer_id,
        m.message_id AS event_id,
        m.sent_at AS event_at,
        'message'::text AS event_type
    FROM messages AS m
    JOIN responses AS r
        ON r.response_id = m.response_id
    JOIN vacancies AS v
        ON v.vacancy_id = r.vacancy_id
    WHERE m.sender_role = 'employer'
      AND m.vacancy_id = r.vacancy_id
      AND m.employer_id = v.employer_id
      AND m.sent_at >= r.created_at
      AND m.sent_at < r.created_at + INTERVAL '7 days'
),
 
communications AS (
    SELECT
        response_id,
        employer_id,
        event_id,
        event_at,
        event_type
    FROM calls_prepared
 
    UNION ALL
 
    SELECT
        response_id,
        employer_id,
        event_id,
        event_at,
        event_type
    FROM messages_prepared
),
 
event_timeline AS (
    SELECT
        response_id,
        employer_id,
        event_id,
        event_at,
        event_type,
 
        ROW_NUMBER() OVER (
            PARTITION BY response_id
            ORDER BY event_at, event_type, event_id
        ) AS event_number,
 
        LAG(event_at) OVER (
            PARTITION BY response_id
            ORDER BY event_at, event_type, event_id
        ) AS previous_event_at,
 
        LEAD(event_type) OVER (
            PARTITION BY response_id
            ORDER BY event_at, event_type, event_id
        ) AS next_event_type,
 
        COUNT(*) OVER (
            PARTITION BY response_id
            ORDER BY event_at, event_type, event_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS communications_from_start,
 
        FIRST_VALUE(event_type) OVER (
            PARTITION BY response_id
            ORDER BY event_at, event_type, event_id
        ) AS first_event_type,
 
        FIRST_VALUE(event_type) OVER (
            PARTITION BY response_id
            ORDER BY event_at DESC, event_type DESC, event_id DESC
        ) AS last_event_type
    FROM communications
),
 
event_stats AS (
    SELECT
        response_id,
        COUNT(*) AS communications_count,
        COUNT(*) FILTER (
            WHERE event_type = 'call'
        ) AS calls_count,
        COUNT(*) FILTER (
            WHERE event_type = 'message'
        ) AS messages_count,
        MIN(event_at) AS first_event_at,
        MAX(first_event_type) AS first_event_type,
        MAX(event_type) FILTER (
            WHERE event_number = 2
        ) AS second_event_type,
        MAX(last_event_type) AS last_event_type,
        MAX(
            EXTRACT(EPOCH FROM (event_at - previous_event_at)) / 3600.0
        ) AS max_interval_hours
    FROM event_timeline
    GROUP BY response_id
),
 
response_mart AS (
    SELECT
        r.response_id,
        v.employer_id,
        v.professional_role,
        r.status AS response_status,
        COALESCE(es.communications_count, 0) AS communications_count,
        COALESCE(es.calls_count, 0) AS calls_count,
        COALESCE(es.messages_count, 0) AS messages_count,
        es.first_event_at,
        es.first_event_type,
        es.second_event_type,
        es.last_event_type,
        EXTRACT(EPOCH FROM (es.first_event_at - r.created_at)) / 3600.0
            AS hours_to_first_event,
        es.max_interval_hours
    FROM responses AS r
    JOIN vacancies AS v
        ON v.vacancy_id = r.vacancy_id
    LEFT JOIN event_stats AS es
        ON es.response_id = r.response_id
),
 
employer_stats AS (
    SELECT
        professional_role,
        employer_id,
        COUNT(*) AS responses_count,
        COUNT(*) FILTER (
            WHERE communications_count > 0
        ) AS responses_with_communication,
        100.0 * COUNT(*) FILTER (
            WHERE communications_count > 0
        ) / COUNT(*) AS communication_share_pct,
        percentile_cont(0.5) WITHIN GROUP (
            ORDER BY hours_to_first_event
        ) FILTER (
            WHERE communications_count > 0
        ) AS median_hours_to_first_event,
        percentile_cont(0.9) WITHIN GROUP (
            ORDER BY hours_to_first_event
        ) FILTER (
            WHERE communications_count > 0
        ) AS p90_hours_to_first_event,
        100.0 * COUNT(*) FILTER (
            WHERE response_status = 'invited'
        ) / COUNT(*) AS invitation_conversion_pct
    FROM response_mart
    GROUP BY
        professional_role,
        employer_id
    HAVING COUNT(*) >= 8
),
 
employer_rating AS (
    SELECT
        professional_role,
        employer_id,
        responses_count,
        responses_with_communication,
        communication_share_pct,
        median_hours_to_first_event,
        p90_hours_to_first_event,
        invitation_conversion_pct,
        DENSE_RANK() OVER (
            PARTITION BY professional_role
            ORDER BY
                communication_share_pct DESC,
                median_hours_to_first_event ASC NULLS LAST
        ) AS place
    FROM employer_stats
)
 
SELECT
    professional_role,
    employer_id,
    responses_count,
    responses_with_communication,
    ROUND(communication_share_pct, 2) AS communication_share_pct,
    ROUND(median_hours_to_first_event::numeric, 2)
        AS median_hours_to_first_event,
    ROUND(p90_hours_to_first_event::numeric, 2)
        AS p90_hours_to_first_event,
    ROUND(invitation_conversion_pct, 2) AS invitation_conversion_pct,
    place
FROM employer_rating
WHERE place IN (1, 2)
ORDER BY
    professional_role,
    place,
    employer_id;
 
/*
Вывод:
 
- Аналитик данных - место 1, employer_id 109
- Аналитик данных - место 2, employer_id 103
- Дата-инженер - место 1, employer_id 106
- Дата-инженер - место 2, employer_id 101
- Продуктовый аналитик - место 1, employer_id 103
- Продуктовый аналитик - место 2, employer_id 102
- Разработчик - место 1, employer_id 112
- Разработчик - место 2, employer_id 104
- Тестировщик - место 1, employer_id 107
- Тестировщик - место 2, employer_id 108

*/

-- ЗАДАНИЕ 5

WITH messages_prepared AS (
    SELECT
        m.message_id,
        m.response_id,
        m.employer_id,
        m.sender_role,
        m.sent_at
    FROM messages AS m
    JOIN responses AS r
        ON r.response_id = m.response_id
    JOIN vacancies AS v
        ON v.vacancy_id = r.vacancy_id
    WHERE m.vacancy_id = r.vacancy_id
      AND m.employer_id = v.employer_id
      AND m.sent_at >= r.created_at
      AND m.sent_at < r.created_at + INTERVAL '7 days'
),
 
messages_with_previous AS (
    SELECT
        message_id,
        response_id,
        employer_id,
        sender_role,
        sent_at,
        LAG(sender_role) OVER (
            PARTITION BY response_id
            ORDER BY sent_at, message_id
        ) AS previous_sender_role,
        LAG(sent_at) OVER (
            PARTITION BY response_id
            ORDER BY sent_at, message_id
        ) AS previous_sent_at
    FROM messages_prepared
),
 
employer_answers AS (
    SELECT
        message_id,
        response_id,
        employer_id,
        EXTRACT(
            EPOCH FROM (sent_at - previous_sent_at)
        ) / 3600.0 AS answer_time_hours
    FROM messages_with_previous
    WHERE sender_role = 'employer'
      AND previous_sender_role = 'applicant'
),
 
employer_stats AS (
    SELECT
        employer_id,
        COUNT(*) AS answers_count,
        AVG(answer_time_hours) AS avg_answer_time_hours,
        percentile_cont(0.5) WITHIN GROUP (
            ORDER BY answer_time_hours
        ) AS median_answer_time_hours,
        percentile_cont(0.9) WITHIN GROUP (
            ORDER BY answer_time_hours
        ) AS p90_answer_time_hours
    FROM employer_answers
    GROUP BY employer_id
)
 
SELECT
    employer_id,
    answers_count,
    ROUND(avg_answer_time_hours::numeric, 2)
        AS avg_answer_time_hours,
    ROUND(median_answer_time_hours::numeric, 2)
        AS median_answer_time_hours,
    ROUND(p90_answer_time_hours::numeric, 2)
        AS p90_answer_time_hours
FROM employer_stats
ORDER BY
    median_answer_time_hours,
    employer_id;
 
/*
Вывод:
 
- общее количество найденных ответов - 749
- минимальная медиана времени ответа у работодателя с employer_id 107
- значение его медианы - 3.93 часа
*/

-- Блок Г. Сложные типы данных

-- ЗАДАНИЕ 6.1

WITH employer_calls AS (
    SELECT
        c.call_id,
        c.status,
        c.call_tags
    FROM calls AS c
    JOIN responses AS r
        ON r.response_id = c.response_id
    JOIN vacancies AS v
        ON v.vacancy_id = r.vacancy_id
    WHERE c.caller_role = 'employer'
      AND c.vacancy_id = r.vacancy_id
      AND c.employer_id = v.employer_id
      AND c.call_at >= r.created_at
      AND c.call_at < r.created_at + INTERVAL '7 days'
),
 
checked_calls AS (
    SELECT
        call_id,
        status,
        call_tags,
        CASE
            WHEN status = 'successful'
                THEN 'connected' = ANY(call_tags)
                 AND NOT (
                     call_tags && ARRAY[
                         'no_answer',
                         'technical_error'
                     ]::text[]
                 )
 
            WHEN status = 'unsuccessful'
                THEN 'no_answer' = ANY(call_tags)
                 AND NOT (
                     call_tags && ARRAY[
                         'connected',
                         'technical_error'
                     ]::text[]
                 )
 
            WHEN status = 'error'
                THEN 'technical_error' = ANY(call_tags)
                 AND NOT (
                     call_tags && ARRAY[
                         'connected',
                         'no_answer'
                     ]::text[]
                 )
        END AS is_valid
    FROM employer_calls
),
 
valid_calls AS (
    SELECT
        call_id,
        call_tags
    FROM checked_calls
    WHERE is_valid
)
 
SELECT
    COUNT(*) FILTER (
        WHERE 'screening' = ANY(call_tags)
    ) AS screening_calls,
 
    COUNT(*) FILTER (
        WHERE 'interview' = ANY(call_tags)
    ) AS interview_calls,
 
    COUNT(*) FILTER (
        WHERE 'follow_up' = ANY(call_tags)
    ) AS follow_up_calls,
 
    COUNT(*) FILTER (
        WHERE 'details' = ANY(call_tags)
    ) AS details_calls,
 
    COUNT(*) FILTER (
        WHERE call_tags && ARRAY[
            'screening',
            'interview',
            'follow_up',
            'details'
        ]::text[]
    ) AS calls_with_business_tags,
 
    ROUND(
        AVG(cardinality(call_tags))::numeric,
        2
    ) AS avg_tags_per_valid_call
FROM valid_calls;
 
/*
Вывод:
 
- количество звонков с тегом screening - 25
- количество звонков с тегом interview  31
- количество звонков с тегом follow_up - 29
- количество звонков с тегом details - 23
- количество валидных звонков хотя бы с одним бизнес-тегом - 108
- среднее количество тегов на один валидный звонок - 4.00
*/

-- ЗАДАНИЕ 6.2

WITH employer_messages AS (
    SELECT
        m.message_id,
        m.message_meta
    FROM messages AS m
    JOIN responses AS r
        ON r.response_id = m.response_id
    JOIN vacancies AS v
        ON v.vacancy_id = r.vacancy_id
    WHERE m.sender_role = 'employer'
      AND m.vacancy_id = r.vacancy_id
      AND m.employer_id = v.employer_id
      AND m.sent_at >= r.created_at
      AND m.sent_at < r.created_at + INTERVAL '7 days'
),
 
message_data AS (
    SELECT
        message_id,
        COALESCE(message_meta ->> 'channel', 'channel_missing') AS channel,
        message_meta ? 'is_read' AS is_read_present,
        (message_meta ->> 'is_read')::boolean AS is_read,
        jsonb_array_length(
            message_meta -> 'attachments'
        ) AS attachments_count
    FROM employer_messages
)
 
SELECT
    channel,
    COUNT(*) AS messages_count,
    COUNT(*) FILTER (
        WHERE is_read_present
    ) AS messages_with_read_status,
    COUNT(*) FILTER (
        WHERE is_read_present
          AND is_read = false
    ) AS unread_messages,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE is_read_present
              AND is_read = false
        )
        / NULLIF(
            COUNT(*) FILTER (
                WHERE is_read_present
            ),
            0
        ),
        2
    ) AS unread_share_pct,
    COUNT(*) FILTER (
        WHERE attachments_count > 0
    ) AS messages_with_attachments,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE attachments_count > 0
        ) / COUNT(*),
        2
    ) AS attachments_share_pct
FROM message_data
GROUP BY channel
ORDER BY channel;
 
/*
Вывод:
 
- канал mobile_app:
  количество сообщений - 360
  сообщений с известным признаком прочтения - 360
  непрочитанных сообщений - 36
  доля непрочитанных среди сообщений с известным признаком - 10.00%
  сообщений хотя бы с одним вложением - 14
  доля сообщений с вложением - 3.89%
 
- канал web:
  количество сообщений - 628
  сообщений с известным признаком прочтения - 628
  непрочитанных сообщений - 52
  доля непрочитанных среди сообщений с известным признаком - 8.28%
  сообщений хотя бы с одним вложением - 25
  доля сообщений с вложением - 3.98%
 
сообщений без указанного канала не найдено
*/

-- Блок Д. Самостоятельное исследование

-- ЗАДАНИЕ 7

/*
гипотеза 1:
 
по откликам с приглашением работодатель чаще начинает коммуникацию
в первые 7 дней и быстрее выходит на связь, чем по остальным откликам.
 
для проверки нужно сравнить долю откликов с коммуникацией, медианное время
до первой коммуникации и долю первых коммуникаций в течение 24 часов.
 
 
гипотеза 2:
 
по откликам с приглашением коммуникация будет более интенсивная:
в среднем по ним происходит больше событий и чаще используются сразу оба типа коммуникации - звонки и сообщения.
 
для проверки нужно сравнить среднее количество коммуникаций, звонков
и сообщений, а также долю откликов с обоими типами коммуникации.
*/
 
WITH calls_prepared AS (
    SELECT
        c.response_id,
        c.employer_id,
        c.call_id AS event_id,
        c.call_at AS event_at,
        'call'::text AS event_type
    FROM calls AS c
    JOIN responses AS r
        ON r.response_id = c.response_id
    JOIN vacancies AS v
        ON v.vacancy_id = r.vacancy_id
    WHERE c.caller_role = 'employer'
      AND c.vacancy_id = r.vacancy_id
      AND c.employer_id = v.employer_id
      AND c.call_at >= r.created_at
      AND c.call_at < r.created_at + INTERVAL '7 days'
),
 
messages_prepared AS (
    SELECT
        m.response_id,
        m.employer_id,
        m.message_id AS event_id,
        m.sent_at AS event_at,
        'message'::text AS event_type
    FROM messages AS m
    JOIN responses AS r
        ON r.response_id = m.response_id
    JOIN vacancies AS v
        ON v.vacancy_id = r.vacancy_id
    WHERE m.sender_role = 'employer'
      AND m.vacancy_id = r.vacancy_id
      AND m.employer_id = v.employer_id
      AND m.sent_at >= r.created_at
      AND m.sent_at < r.created_at + INTERVAL '7 days'
),
 
communications AS (
    SELECT
        response_id,
        employer_id,
        event_id,
        event_at,
        event_type
    FROM calls_prepared
 
    UNION ALL
 
    SELECT
        response_id,
        employer_id,
        event_id,
        event_at,
        event_type
    FROM messages_prepared
),
 
communication_stats AS (
    SELECT
        response_id,
        COUNT(*) AS communications_count,
        COUNT(*) FILTER (
            WHERE event_type = 'call'
        ) AS calls_count,
        COUNT(*) FILTER (
            WHERE event_type = 'message'
        ) AS messages_count,
        MIN(event_at) AS first_event_at
    FROM communications
    GROUP BY response_id
),
 
response_mart AS (
    SELECT
        r.response_id,
        CASE
            WHEN r.status = 'invited' THEN 'invited'
            ELSE 'other'
        END AS response_group,
        COALESCE(cs.communications_count, 0) AS communications_count,
        COALESCE(cs.calls_count, 0) AS calls_count,
        COALESCE(cs.messages_count, 0) AS messages_count,
        EXTRACT(
            EPOCH FROM (cs.first_event_at - r.created_at)
        ) / 3600.0 AS hours_to_first_event
    FROM responses AS r
    LEFT JOIN communication_stats AS cs
        ON cs.response_id = r.response_id
)
 
SELECT
    response_group,
    COUNT(*) AS responses_count,
 
    COUNT(*) FILTER (
        WHERE communications_count > 0
    ) AS responses_with_communication,
 
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE communications_count > 0
        ) / COUNT(*),
        2
    ) AS communication_share_pct,
 
    ROUND(
        percentile_cont(0.5) WITHIN GROUP (
            ORDER BY hours_to_first_event
        ) FILTER (
            WHERE communications_count > 0
        )::numeric,
        2
    ) AS median_hours_to_first_event,
 
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE hours_to_first_event <= 24
        )
        / NULLIF(
            COUNT(*) FILTER (
                WHERE communications_count > 0
            ),
            0
        ),
        2
    ) AS first_event_within_24h_pct,
 
    ROUND(
        AVG(communications_count) FILTER (
            WHERE communications_count > 0
        ),
        2
    ) AS avg_communications_count,
 
    ROUND(
        AVG(calls_count) FILTER (
            WHERE communications_count > 0
        ),
        2
    ) AS avg_calls_count,
 
    ROUND(
        AVG(messages_count) FILTER (
            WHERE communications_count > 0
        ),
        2
    ) AS avg_messages_count,
 
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE calls_count > 0
              AND messages_count > 0
        )
        / NULLIF(
            COUNT(*) FILTER (
                WHERE communications_count > 0
            ),
            0
        ),
        2
    ) AS both_event_types_share_pct
FROM response_mart
GROUP BY response_group
ORDER BY response_group;
 
/*
Вывод по гипотезе 1:
 
в группе invited было 92 отклика, а в группе other - 536 откликов
 
доля откликов с коммуникацией составила 58.70% для invited и 61.19% для other
медианное время до первой коммуникации составило 51.08 часа для invited и 54.67 часа для other
доля первых коммуникаций в течение 24 часов составила 33.33% для invited и 31.71% для other
 
по откликам с приглашением работодатели немного быстрее начинали общение,
но доля откликов с коммуникацией оказалась ниже, чем в группе other, поэтому гипотеза в такой формулировке не подтверждается.
 
 
Вывод по гипотезе 2:
 
показатели рассчитаны по 54 откликам с коммуникацией в группе invited и по 328 откликам с коммуникацией в группе other
 
среднее количество коммуникаций составило 2.78 для invited и 2.88 для other 
среднее количество звонков в обеих группах составило 0.28, а среднее количество сообщений - 2.50 для invited и 2.60 для other
 
доля откликов, где были и звонки, и сообщения, составила 14.81% для invited и 17.38% для other
 
в откликах с приглашением коммуникация не была более интенсивной:
среднее количество событий и доля откликов с обоими типами коммуникации
оказались немного ниже, поэтому гипотеза не подтверждается.
*/

-- ЗАДАНИЕ 8

/*
Итог исследования:
 
в первые 7 дней после отклика коммуникация работодателя была по 382 из 628 откликов, то есть по 246 откликам её не было.
при подготовке данных я нашла 8 звонков без response_id: сам звонок мог состояться, но связать его с конкретным откликом нельзя.
работодатели общаются с кандидатами не только звонками: среди сообщений работодателя за первые 7 дней было 628 сообщений через web и 360 через mobile_app.
скорость ответа различается между работодателями: у employer_id 107 медианное время ответа на сообщение кандидата составило 3.93 часа.
также есть различия внутри направлений: среди дата-инженеров доля откликов с коммуникацией составила 70.00% у employer_id 106 и 45.83% у employer_id 101.
по откликам с приглашением первая коммуникация начиналась немного быстрее:
медиана составила 51.08 часа против 54.67 часа у остальных откликов, но доля откликов с коммуникацией была ниже - 58.70% против 61.19%.
поэтому я не вижу подтверждения, что приглашения связаны с более частой или более интенсивной коммуникацией: 
среднее число событий среди откликов с коммуникацией составило 2.78 против 2.88.

мы рассматриваем только первые 7 дней и не знаем, когда именно статус отклика
изменился на «приглашён», 
поэтому сравнение показывает связь в данных, но не доказывает, что коммуникации привели к приглашению.
дальше я бы запросила историю изменения статусов откликов и проверила, какие коммуникации произошли именно до приглашения.
*/