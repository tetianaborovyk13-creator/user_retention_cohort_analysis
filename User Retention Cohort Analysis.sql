select *
from cohort_events_raw cer 
limit 10;

--

select *
from cohort_users_raw cur 
limit 10;

--Створити CTE для очищення дат у cohort_users_raw

with date_with_no_time as (
      select user_id,
           trim(split_part(signup_datetime, ' ', 1)) as signup_date --Прибрали зайві пробіли і час
      from cohort_users_raw cur),
    clean_date as (
      select user_id,
             regexp_replace(signup_date, '[/.]', '-', 'g') as signup_date --Замінили всі розділювачі на дефіс
      from date_with_no_time),
    normalized_date as (
      select user_id,
            case when length(split_part(signup_date, '-', 3)) = 2 --Задали умову, що довжина року (третя частина) має лише два знаки
            then split_part(signup_date, '-', 1) || '-' || split_part(signup_date, '-', 2) ||'-20'||''||split_part(signup_date, '-', 3) 
           --За попередньої умови потрібно додати 20 перед третьою частиною
            else signup_date
            end as signup_date
      from clean_date)
select user_id,
       to_date(signup_date, 'dd-mm-yyyy') as signup_timestamp --Змінили формат на дату
from normalized_date nm
order by user_id
   ;

--Створити CTE для очищення дат у cohort_events_raw

with event_date_with_no_time as (
      select user_id,
             trim(split_part(event_datetime, ' ', 1)) as event_date
      from cohort_events_raw),
    clean_event_date as (
      select user_id,
             regexp_replace(event_date, '[/.]', '-', 'g') as event_date
      from event_date_with_no_time),
    event_normalized_date as (
      select user_id,
             case when length(split_part(event_date, '-', 3)) = 2
             then split_part(event_date, '-', 1) || '-' || split_part(event_date, '-', 2) ||'-20'||''||split_part(event_date, '-', 3) 
             else event_date
             end as event_date
     from clean_event_date)
select user_id,
       to_date(event_date, 'dd-mm-yyyy') as event_timestamp
from event_normalized_date
order by user_id
   ;

-- Об'єднання таблиць та побудова когортної таблиці
with date_with_no_time as (
      select user_id,
           trim(split_part(signup_datetime, ' ', 1)) as signup_date
      from cohort_users_raw cur),
    clean_date as (
      select user_id,
             regexp_replace(signup_date, '[/.]', '-', 'g') as signup_date 
      from date_with_no_time),
    normalized_date as (
      select user_id,
            case when length(split_part(signup_date, '-', 3)) = 2
            then split_part(signup_date, '-', 1) || '-' || split_part(signup_date, '-', 2) ||'-20'||''||split_part(signup_date, '-', 3) 
            else signup_date
            end as signup_date
      from clean_date)
,
    event_date_with_no_time as (
      select user_id,
             event_type,
             trim(split_part(event_datetime, ' ', 1)) as event_date
      from cohort_events_raw
      where event_type is not null
      and event_type !='test_event'),
    clean_event_date as (
      select user_id,
             event_type,
             regexp_replace(event_date, '[/.]', '-', 'g') as event_date 
      from event_date_with_no_time),
    event_normalized_date as (
      select user_id,
             event_type,
             case when length(split_part(event_date, '-', 3)) = 2
             then split_part(event_date, '-', 1) || '-' || split_part(event_date, '-', 2) ||'-20'||''||split_part(event_date, '-', 3) 
             else event_date
             end as event_date
     from clean_event_date),
     final_table as
   (select cur.promo_signup_flag as promo_signup_flag,
       nd.user_id,
       to_date(nd.signup_date, 'dd-mm-yyyy') as cohort_month,
       to_date(e.event_date, 'dd-mm-yyyy') as event_month,
        extract(year from age(to_date(e.event_date, 'dd-mm-yyyy'), to_date(nd.signup_date, 'dd-mm-yyyy'))) * 12 +            --Розрахували різницю в місяцях (month_offset) між подією та реєстрацією
        extract(month from age(date_trunc('month', to_date(e.event_date, 'dd-mm-yyyy')), date_trunc('month', to_date(nd.signup_date, 'dd-mm-yyyy')))) as month_offset --Перетворили дати у формат рік-місяць
       from normalized_date nd
   join event_normalized_date e on e.user_id = nd.user_id
   join cohort_users_raw cur on  cur.user_id = nd.user_id
   order by nd.user_id)                     --Створили тимчасову об'єднану таблицю з колонками, необхідними для наступного кроку
 select promo_signup_flag,
        date_trunc('month', cohort_month)::date as cohort_month,               --Перетворили дати у формат рік-місяць
        month_offset,
        count(distinct user_id) as users_total  --Розрахували users_total
        from final_table ft
        where cohort_month is not null    --Виключили користувачів з відсутньою датою реєстрації
        and event_month is not null       --Виключили події з відсутньою датою
        and date_trunc('month', event_month)::date between '2025-01-01' and '2025-06-01'  --Обмежили період спостереження: січень-червень 2025
        group by 1, 2, 3                   --Додали групування
        order by 1, 2, 3                   --Відсортували
 ;

   
