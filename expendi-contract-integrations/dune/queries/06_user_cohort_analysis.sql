-- Query 6: User Cohort Analysis
-- Analyzes user retention by cohort week for TimeLock
-- Note: Replace 'expendi_base' with your actual namespace after Dune decoding

with first_lock as (
    select
        depositor,
        min(date_trunc('week', evt_block_time)) as cohort_week
    from expendi_base.TimeLock_evt_LockCreated
    group by 1
),

activity as (
    select
        depositor,
        date_trunc('week', evt_block_time) as activity_week
    from expendi_base.TimeLock_evt_LockCreated
)

select
    f.cohort_week,
    count(distinct f.depositor) as cohort_size,
    count(distinct case
        when a.activity_week = f.cohort_week + interval '1' week
        then a.depositor
    end) as retained_week_1,
    count(distinct case
        when a.activity_week = f.cohort_week + interval '2' week
        then a.depositor
    end) as retained_week_2,
    count(distinct case
        when a.activity_week = f.cohort_week + interval '4' week
        then a.depositor
    end) as retained_week_4,
    count(distinct case
        when a.activity_week = f.cohort_week + interval '8' week
        then a.depositor
    end) as retained_week_8
from first_lock f
left join activity a
    on f.depositor = a.depositor
where f.cohort_week >= now() - interval '180' day
group by 1
order by 1 desc
