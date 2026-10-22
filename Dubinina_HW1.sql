-- ============================================================
-- Домашнее задание к лекции «SQL. Введение»
-- Школа Аналитиков · учебная база hh_school
-- Автор: [ФИО]
-- ============================================================
-- Формат: задания по порядку, каждое начинается с комментария
-- с номером; под каждым запросом — вывод (2–3 предложения).
-- Запрос без вывода не засчитывается.
-- ============================================================

SET search_path TO hh_school;

-- ============================================================
-- БЛОК А. Разминка: термины и структура (текстом)
-- ============================================================

-- ЗАДАНИЕ А1
-- 1. Категория и конкретный тип колонок:
--    vacancies.salary_from        — категория: числовая   тип: INTEGER
--    vacancies.vacancy_name       — категория: строковая   тип: TEXT
--    vacancies.published_at       — категория: дата и время   тип: TIMESTAMP NOT NULL
--    employers.is_accredited_it   — категория: логическая   тип: BOOLEAN
--    responses.created_at         — категория: дата и время   тип: TIMESTAMP NOT NULL
--
-- 2. Первичные ключи таблиц:
--    areas: area_id
--    employers: employer_id
--    vacancies: vacancy_id
--    vacancy_details: vacancy_id (чем особенный: одновременно и FK, ссылается на PK vacancies)
--    responses: response_id
--
-- 3. Почему vacancy_name не может быть первичным ключом:
--    так как PK должен быть уникальным, а vacancy_name имеет повторы
--    Запрос для подтверждения числом:

-- запрос:
--select vacancy_name, count(*) from hh_school.vacancies
--group by(vacancies.vacancy_name);

-- Вывод:
--vacancy_name                |count|
----------------------------+-----+
--Senior аналитик данных      |    5|
--Стажёр: разработчик         |    5|
--Стажёр: дата-инженер        |    3|
--Junior тестировщик          |    1|
--Junior продуктовый аналитик |    1|
--Senior тестировщик          |    1|
--Разработчик                 |    5|
--Junior дата-инженер         |    3|
--Продуктовый аналитик        |    4|
--Junior разработчик          |    3|
--Аналитик данных             |    4|
--Тестировщик                 |    2|
--Стажёр: тестировщик         |    3|
--Senior разработчик          |    2|
--Junior аналитик данных      |    1|
--Стажёр: аналитик данных     |    6|
--Senior дата-инженер         |    1|
--Стажёр: продуктовый аналитик|    2|
--
-- 4. Что произойдёт при записи строки «по договорённости» в salary_from:
--    поскольку salary_from имеет тип INTEGER, строку "по договорённости" записать нельзя, произойдет ошибка синтаксиса 
--    но можно считать "по договоренности"= NULL
--    такое поведение субд хорошее, так как помогает избежать разрозненности типов данных и ошибок в дальнейшем


-- ============================================================
-- БЛОК Б. Первые запросы: SELECT, WHERE, ORDER BY
-- ============================================================

-- ЗАДАНИЕ Б1
-- Запрос: experience
select distinct experience from vacancies;

-- Запрос: employment
select distinct employment from vacancies;

-- Запрос: professional_role
select distinct professional_role from vacancies;

-- Вывод:
-- experience - 3 различных значения
-- employment - 3 различных значения
-- professional_role - 5 различных значений
-- одинаковых значений, записанных по-разному, не обнаружено
-- NULL не обнаружено
-- явных проблем с качеством данных нет


-- ЗАДАНИЕ Б2
-- Запрос 1: стажировки в Москве без опыта, вакансия открыта
select v.vacancy_id, v.vacancy_name, v.salary_from, v.published_at 
from vacancies as v
join areas as a on v.area_id = a.area_id
where v.experience = 'Нет опыта' 
	and v.employment = 'Стажировка' 
--	and a.area_name = 'Москва' 
	and v.closed_at is NULL
order by v.published_at desc;

-- Запрос 2: топ-10 вакансий по salary_from
select vacancy_name, professional_role, salary_from 
from vacancies
order by salary_from desc nulls last
limit 10;

-- Вывод:
-- поиск выдал 8 вакансий в Москве, 10 вакансий без условия на Москву
--


-- ЗАДАНИЕ Б3
-- Ловушка 1. NULL — выполнить и объяснить результат
SELECT count(*) FROM vacancies WHERE closed_at = NULL;
SELECT count(*) FROM vacancies WHERE closed_at IS NULL;

-- Ловушка 2. AND / OR — выполнить и объяснить результат
SELECT count(*) FROM vacancies
WHERE area_id = 1 OR area_id = 2 AND experience = 'Нет опыта';

SELECT count(*) FROM vacancies
WHERE (area_id = 1 OR area_id = 2) AND experience = 'Нет опыта';

-- Вывод:
-- ловушка 1
-- выражение closed_at = NULL допустимо синтаксически, поэтому PostgreSQL не выдаёт ошибку
-- результат любого обычного сравнения с NULL - UNKNOWN
-- условие WHERE оставляет только строки, для которых выражение равно TRUE, поэтому строки с результатом UNKNOWN отбрасываются, и count(*) возвращает 0
-- это опасно, так как запрос успешно выполняется и выдаёт правдоподобное число, хотя условие составлено неправильно
-- для NULL значений есть специальный оператор - is null, а не = null
-- сравнение с null никогда не истинно, оно не обозначает 0 или пустую строку
-- null в колонке closed_at означает, что объявление еще действительно, поиск сотрудника не завершен
-- ловушка 2
-- оператор AND имеет более высокий приоритет, чем OR
-- считаем значения, где (area_id = 1) или (area_id = 2 и experience = 'Нет опыта')
-- запрос 2 отвечает на вопрос «вакансии из Москвы или Санкт-Петербурга, но обязательно без опыта»

-- ============================================================
-- БЛОК В. Агрегации и метрики
-- ============================================================

-- ЗАДАНИЕ В1 
-- Запрос 1: счётчики (строки, зарплата указана, направления, работодатели)
select count(*) as rows_count, 
	count(salary_from) AS salary_exist_count,
	count(distinct v.professional_role) as professional_role_count, 
	count(distinct e.employer_name) as employers_count
from vacancies v
join employers as e on v.employer_id = e.employer_id;

-- Запрос 2: доля активных вакансий (без JOIN)
with vacancy_counts as(
select count(*) filter (where closed_at is null) as open_count,
	count(*) filter (where closed_at is not null) as closed_count
from vacancies
)
select open_count, 
	closed_count,
	round(100.0 * open_count::numeric/nullif(closed_count+open_count, 0), 1) as percentage_of_open
from vacancy_counts;

-- Вывод:
-- count(*) - считает строки (с NULL тоже) - 52 значения
-- count(колонка) - считает непустые значения в колонке - в 44 из 52 строках указана нижняя границы зарплаты, пропускаем NULL
-- count(DISTINCT колонка) - считает различные непустые значения - 5 различных непустых направлений, 
-- 12 различных работодателей разместили свои вакансии, NULL не учитывается
-- сейчас открыто 33 из 52 вакансий - это 63.5%.


-- ЗАДАНИЕ В2
-- Запрос 1: направления — вакансии, работодатели, средняя зарплата
select professional_role, 
count(*) as vacancies_count, 
count(distinct employer_id) emloyers_count, 
round(avg(salary_from),0) as avg_salary_from
from vacancies
group by professional_role
order by vacancies_count desc;
-- Запрос 2: то же, только направления с ≥ 5 открытыми вакансиями (WHERE + HAVING)
select professional_role, 
count(*) as vacancies_count, 
count(distinct employer_id) emloyers_count, 
round(avg(salary_from),0) as avg_salary_from
from vacancies
where closed_at is null 
group by professional_role
having count(*) >= 5
order by vacancies_count desc;

-- Вывод:
-- аналитик данных и разработчик занимают больше половины рынка учебной базы
-- соискатель мог бы предположить, что спрос сильнее всего сосредоточен в этих двух направлениях
-- для вывода о рынке в целом не хватает сведений о полноте и репрезентативности базы: 
-- периоде сбора, регионах, источниках вакансий и общем объёме реального рынка
-- кроме того, число вакансий показывает спрос работодателей, но ничего не говорит о числе соискателей и конкуренции
-- WHERE фильтрует строки до группировки, поэтому в группы попадают только открытые вакансии
-- HAVING фильтрует группы после неё и оставляет направления, в которых насчитано не менее пяти открытых вакансий
-- Написать WHERE count(*) >= 5 невозможно: в момент выполнения WHERE группы ещё не построены и
-- считать нечего, работает последовательность выполнения запроса
-- на какую среднюю нижнюю границу зарплаты может рассчитывать соискатель среди вакансий данного направления?
-- это значение не отвечает на вопросы:
-- какова средняя зарплата по всем вакансиям направления
-- сколько в среднем реально получают сотрудники
-- какую зарплату гарантированно получит соискатель
-- какова средняя верхняя граница зарплаты

-- ============================================================
-- БЛОК Г. Соединение таблиц
-- ============================================================

-- ЗАДАНИЕ Г1
-- Запрос: топ-5 по salary_from с названием компании и городом (псевдонимы таблиц)
select v.vacancy_name, 
e.employer_name, 
a.area_name, 
v.salary_from
from vacancies as v
left join areas as a
on v.area_id = a.area_id
left join employers as e
on v.employer_id = e.employer_id
order by v.salary_from desc nulls last
limit 5;
-- Вывод:
-- если в условии соединения написать просто area_id, PostgreSQL не поймёт, из какой таблицы нужно взять эту колонку, 
-- поскольку area_id присутствует и в vacancies, и в areas: ON area_id = area_id
-- будет получена ошибка, псевдонимы устраняют неоднозначность: 
-- v.area_id - идентификатор города из вакансии, a.area_id - идентификатор города из справочника areas


-- ЗАДАНИЕ Г2
-- Запрос 1: все работодатели, число вакансий и откликов (LEFT JOIN)
select e.employer_name,
count(distinct v.vacancy_id) as vacancies_count,
count(r.response_id) as responses_count
from employers as e
left join vacancies as v
on v.employer_id = e.employer_id
left join  responses as r
on v.vacancy_id = r.vacancy_id
group by e.employer_id, e.employer_name
order by responses_count desc;
-- Запрос 2: тот же запрос с INNER JOIN
select e.employer_name,
count(distinct v.vacancy_id) as vacancies_count,
count(r.response_id) as responses_count
from employers as e
inner join vacancies as v
on v.employer_id = e.employer_id
inner join  responses as r
on v.vacancy_id = r.vacancy_id
group by e.employer_id, e.employer_name
order by responses_count desc;

-- Вывод:
-- количество вакансий приходится считать через count(DISTINCT ...), а не через count(*)
-- из-за связи 1 вакансия - много откликов, distinct позволяет учесть вакансию только один раз
-- компания ГринЭнерго исчезла во втором запросе, так как содержит нулевое число откликов
-- но у нее есть 1 вакансия, следовательно, при исчезновении компании мы потеряем важную статистику отсутствия откликов при наличии вакансии
-- если важно, чтобы все строки левой таблицы сохранялись (даже нулевые), то нужно выбрать left join
-- если это не важно и нужны только строки, существующие в обеих таблицах, то выбор - inner join


-- ============================================================
-- БЛОК Д. Функции и финальный кейс
-- ============================================================

-- ЗАДАНИЕ Д1
-- Запрос: помесячная динамика откликов и конверсия
-- (месяц как дата, условный агрегат, nullif в знаменателе)
select date_trunc('month', created_at)::date as month,
count(*) as responses_count,
count(*) filter (where status = 'invited') as invited_count,
round(100.0*(count(*) filter (where status = 'invited'))/nullif(count(*),0),1) as conv
from responses
group by month
order by month;


-- Вывод:
-- максимальная конверсия была в июне - 19.5%
-- этому месяцу можно доверять больше, чем проценту, рассчитанному по нескольким откликам:
-- количество откликов в июне составило 118, а приглашенных 23, 
-- что является одной из крупнейших выборок в таблице
-- однако одного месяца все арвно недостаточно, чтобы считать 19.5% устойчивым результатом и планировать выбор
-- в августе самая минимальная конверсия - 7.3%, выборка содержит 41 отклик.
-- в таблице присутствуют не все дни августа(до 15го), поэтому этот месяц не можем считать как полный и можем исключить из выводов
-- проверка полноты августа:
select max(created_at) as last_response_at
from responses;

-- ЗАДАНИЕ Д2
-- Запрос: таблица по направлениям (вакансии, отклики, приглашения,
-- откликов на вакансию, конверсия)
select v.professional_role,
count(distinct v.vacancy_id) as vacancies_count,
count(r.response_id) as responses_count,
count(r.response_id) filter (where r.status = 'invited') as invited_count,
round(1.0*count(r.response_id)/nullif(count(distinct v.vacancy_id),0),1) as responses_per_vacancy,
round(100.0*(count(r.response_id) filter (where r.status = 'invited'))/nullif(count(r.response_id),0),1) as conv
from vacancies as v
left join responses as r
on v.vacancy_id = r.vacancy_id
group by v.professional_role;

-- Письменные ответы:
-- 1. Совпадает ли направление с наибольшим числом вакансий с направлением
--    с наибольшей конверсией?
-- не совпадает: направление с наибольшим числом вакансий (16) - аналитик данных, направление с наибольшей конверсией (35.9%) - тестировщик
-- 2. Какое направление выбрать и почему (опираясь на два столбца):
-- лучше выбрать направление тестировщик, так как конверсия выше, а количсетво откликов на вакансию одно из минимальных (5.6)
--  такое сочетание может указывать на более высокую вероятность получить приглашение при относительно небольшой конкуренции
-- 3. Оговорка к выводу:
-- данные не показывают квалификацию и число уникальных соискателей
-- несколько откликов могут принадлежать одному человеку, а высокая конверсия может объясняться требованиями к кандидатам или небольшим объёмом наблюдений
-- поэтому по этим показателям нельзя точно оценить личные шансы конкретного соискателя


-- ============================================================
-- БЛОК Е. Со звёздочкой
-- ============================================================

-- ЗАДАНИЕ Е1
-- Исходный запрос (выполнить и посмотреть результат):
-- SELECT v.professional_role,
-- count(*) AS vacancies,
-- sum(v.salary_from) AS total_salary,
-- count(r.response_id) / count(*) AS responses_per_vacancy
-- FROM vacancies v
-- JOIN responses r ON v.vacancy_id = r.vacancy_id
-- WHERE v.closed_at = NULL
-- GROUP BY 1;
--
-- ЗАДАНИЕ Е1
-- Ошибки исходного запроса:
--
-- 1. WHERE v.closed_at = NULL некорректно синтаксически
-- результат сравнения с NULL равен UNKNOWN, поэтому запрос не вернёт строк
-- необходимо использовать IS NULL
--
-- 2. JOIN исключает открытые вакансии, у которых нет откликов
-- чтобы они вошли в число вакансий и дали 0 откликов, нужен LEFT JOIN.
--
-- 3. после прямого соединения с responses одна вакансия повторяется по одному
-- разу на каждый отклик, поэтому count(*) считает строки соединения,ма не количество вакансий.
--
-- 4. по той же причине sum(v.salary_from) многократно учитывает зарплату
-- вакансии, если на неё поступило несколько откликов
--
-- 5. count(r.response_id) / count(*) не рассчитывает среднее число откликов на вакансию
-- при JOIN обе функции фактически считают строки откликов, поэтому результат обычно будет равен 1
--
-- 6. деление целых значений приводит к потере дробной части
--
-- 7. GROUP BY 1 зависит от позиции колонки в SELECT, лучше явно указывать переменную
--
-- Исправленный запрос:
 
select v.professional_role,
count(distinct v.vacancy_id) as vacancies_count,
round(avg(v.salary_from), 0) as avg_salary_from,
round(1.0*sum(coalesce(r.responses_count, 0))::numeric / nullif(count(distinct v.vacancy_id), 0), 1) as responses_per_vacancy
from vacancies as v
left join (
	select vacancy_id,
	count(*) as responses_count
	from responses
	group by vacancy_id
	) as r
on r.vacancy_id = v.vacancy_id
where v.closed_at is null
group by v.professional_role
order by v.professional_role;

-- Какие два правила из лекции защитили бы от этих ошибок при написании запроса:
-- 1. null проверять только через is null или is not null, а не через
-- обычные операторы сравнения = и <>
-- 2. перед JOIN определить гранулярность результата и проверить тип связи
-- если связь 1:N размножает строки, дочернюю таблицу нужно предварительно агрегировать
-- если нужны объекты без связанных записей, следует использовать LEFT JOIN
