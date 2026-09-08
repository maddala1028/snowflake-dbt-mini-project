{{ config(
    materialized = 'table',
    tags = ['gold', 'dimension', 'date']
) }}

with date_spine as (

    {{ dbt_utils.date_spine(
        datepart = "day",
        start_date = "cast('2020-01-01' as date)",
        end_date = "cast('2031-01-01' as date)"
    ) }}

)

select
    to_number(to_char(date_day, 'YYYYMMDD')) as date_key,
    date_day::date as calendar_date,
    year(date_day) as calendar_year,
    quarter(date_day) as calendar_quarter,
    month(date_day) as month_number,
    monthname(date_day) as month_name,
    weekiso(date_day) as iso_week_number,
    dayofmonth(date_day) as day_of_month,
    dayofweekiso(date_day) as iso_day_of_week,
    dayname(date_day) as day_name,
    iff(dayofweekiso(date_day) in (6, 7), true, false) as is_weekend,
    date_trunc('month', date_day)::date as month_start_date,
    last_day(date_day, 'month')::date as month_end_date

from date_spine
