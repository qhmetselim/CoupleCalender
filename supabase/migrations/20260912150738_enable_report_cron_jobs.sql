-- Supabase Cron is optional at project creation time. The development project
-- enables pg_cron here so the report jobs are version-controlled as well.
create extension if not exists pg_cron;

do $schedule$
declare
    existing_job record;
begin
    for existing_job in
        select jobid
        from cron.job
        where jobname in ('couplecalender-monthly-reports', 'couplecalender-yearly-reports')
    loop
        perform cron.unschedule(existing_job.jobid);
    end loop;

    perform cron.schedule(
        'couplecalender-monthly-reports',
        '15 2 1 * *',
        'select private.run_monthly_report_cron()'
    );
    perform cron.schedule(
        'couplecalender-yearly-reports',
        '30 2 1 1 *',
        'select private.run_yearly_report_cron()'
    );
end
$schedule$;
