-- ============================================================================
-- PROJECT: Customer Operations & SLA Performance Analysis (T-SQL / SSMS)
-- ============================================================================

IF OBJECT_ID('tempdb..#support_tickets') IS NOT NULL
    DROP TABLE #support_tickets;

CREATE TABLE #support_tickets (
    ticket_id INT PRIMARY KEY,
    customer_region VARCHAR(30),
    issue_category VARCHAR(40),
    priority_level VARCHAR(15),
    assigned_agent VARCHAR(30),
    created_at DATETIME,
    resolved_at DATETIME,
    sla_target_hours INT,
    csat_score INT
);

INSERT INTO #support_tickets VALUES
(101, 'East',  'Billing & Refunds', 'High',     'Aarav', '2026-10-01 09:00:00', '2026-10-01 12:30:00', 4,  5),
(102, 'North', 'Account Access',    'Critical', 'Priya', '2026-10-01 10:15:00', '2026-10-01 13:00:00', 2,  3),
(103, 'South', 'Technical Bug',     'Medium',   'Rohan', '2026-10-01 11:00:00', '2026-10-02 15:00:00', 24, 4),
(104, 'East',  'Delivery Delay',    'High',     'Aarav', '2026-10-02 14:00:00', '2026-10-02 19:30:00', 4,  2),
(105, 'West',  'Billing & Refunds', 'Low',      'Sneha', '2026-10-02 16:00:00', '2026-10-03 10:00:00', 48, 5),
(106, 'North', 'Technical Bug',     'Critical', 'Priya', '2026-10-03 08:30:00', '2026-10-03 09:45:00', 2,  5),
(107, 'East',  'Account Access',    'High',     'Aarav', '2026-10-03 17:30:00', '2026-10-04 01:00:00', 4,  2),
(108, 'South', 'Delivery Delay',    'Medium',   'Rohan', '2026-10-04 10:00:00', '2026-10-05 08:00:00', 24, 4),
(109, 'West',  'Billing & Refunds', 'High',     'Sneha', '2026-10-04 12:00:00', '2026-10-04 15:15:00', 4,  5),
(110, 'North', 'Delivery Delay',    'Critical', 'Priya', '2026-10-05 18:00:00', '2026-10-05 22:30:00', 2,  1),
(111, 'East',  'Technical Bug',     'High',     'Aarav', '2026-10-06 09:30:00', '2026-10-06 16:00:00', 4,  3),
(112, 'South', 'Account Access',    'Low',      'Rohan', '2026-10-06 11:00:00', '2026-10-07 09:00:00', 48, 5),
(113, 'West',  'Technical Bug',     'High',     'Sneha', '2026-10-07 13:00:00', '2026-10-07 16:45:00', 4,  4),
(114, 'East',  'Billing & Refunds', 'Critical', 'Priya', '2026-10-08 15:00:00', '2026-10-08 18:30:00', 2,  2),
(115, 'North', 'Account Access',    'Medium',   'Rohan', '2026-10-09 10:00:00', NULL,                  24, NULL);

-- 1. DATA QUALITY & HYGIENE CHECK
SELECT 
    COUNT(*) AS total_tickets,
    COUNT(resolved_at) AS closed_tickets,
    COUNT(*) - COUNT(resolved_at) AS open_backlog_tickets,
    COUNT(*) - COUNT(csat_score) AS missing_csat_responses
FROM #support_tickets;

-- 2. CORE KPI: SLA COMPLIANCE RATE BY PRIORITY
SELECT 
    priority_level,
    COUNT(*) AS closed_tickets,
    CAST(AVG(DATEDIFF(MINUTE, created_at, resolved_at) / 60.0) AS DECIMAL(5,1)) AS avg_resolution_hrs,
    SUM(CASE WHEN DATEDIFF(MINUTE, created_at, resolved_at) / 60.0 <= sla_target_hours THEN 1 ELSE 0 END) AS within_sla,
    CAST(
        100.0 * SUM(CASE WHEN DATEDIFF(MINUTE, created_at, resolved_at) / 60.0 <= sla_target_hours THEN 1 ELSE 0 END) / COUNT(*) 
    AS DECIMAL(5,1)) AS sla_compliance_pct
FROM #support_tickets
WHERE resolved_at IS NOT NULL
GROUP BY priority_level
ORDER BY sla_compliance_pct ASC;

-- 3. REGIONAL BOTTLENECK & CSAT CORRELATION
SELECT 
    customer_region,
    COUNT(*) AS ticket_volume,
    CAST(AVG(CAST(csat_score AS FLOAT)) AS DECIMAL(4,2)) AS avg_csat,
    SUM(CASE WHEN DATEDIFF(MINUTE, created_at, resolved_at) / 60.0 > sla_target_hours THEN 1 ELSE 0 END) AS sla_breaches
FROM #support_tickets
WHERE resolved_at IS NOT NULL
GROUP BY customer_region
ORDER BY sla_breaches DESC, avg_csat ASC;

-- 4. AGENT PERFORMANCE & WORKLOAD RANKING (CTE + Window Function)
WITH agent_metrics AS (
    SELECT 
        assigned_agent,
        COUNT(*) AS tickets_handled,
        CAST(AVG(DATEDIFF(MINUTE, created_at, resolved_at) / 60.0) AS DECIMAL(5,1)) AS avg_handle_hrs,
        CAST(AVG(CAST(csat_score AS FLOAT)) AS DECIMAL(4,2)) AS avg_csat,
        CAST(
            100.0 * SUM(CASE WHEN DATEDIFF(MINUTE, created_at, resolved_at) / 60.0 <= sla_target_hours THEN 1 ELSE 0 END) / COUNT(*) 
        AS DECIMAL(5,1)) AS sla_pct
    FROM #support_tickets
    WHERE resolved_at IS NOT NULL
    GROUP BY assigned_agent
)
SELECT 
    assigned_agent,
    tickets_handled,
    avg_handle_hrs,
    sla_pct,
    avg_csat,
    RANK() OVER (ORDER BY sla_pct DESC, avg_csat DESC) AS operational_rank
FROM agent_metrics;

-- 5. ROOT-CAUSE PARETO: WHICH ISSUE DRIVES MOST SLA BREACHES?
WITH breach_counts AS (
    SELECT 
        issue_category,
        COUNT(*) AS breach_total
    FROM #support_tickets
    WHERE resolved_at IS NOT NULL 
      AND DATEDIFF(MINUTE, created_at, resolved_at) / 60.0 > sla_target_hours
    GROUP BY issue_category
)
SELECT 
    issue_category,
    breach_total,
    CAST(100.0 * breach_total / SUM(breach_total) OVER () AS DECIMAL(5,1)) AS pct_of_all_breaches
FROM breach_counts
ORDER BY breach_total DESC;