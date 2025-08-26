# Homework #15: Отчет о профилировании запросов

В этом отчете представлены результаты анализа производительности запросов к датасету [YouTube dataset of dislikes](https://clickhouse.com/docs/en/getting-started/example-datasets/youtube-dislikes).


## 1. Запрос без использования первичного ключа

### SQL-запрос
```sql
SELECT
    title,
    view_count,
    like_count,
    dislike_count,
    round(like_count / dislike_count, 2) AS ratio
FROM otus_default.youtube
WHERE (title ILIKE '%Tutorial%')
    AND (view_count > 1000)
    AND (dislike_count > 0)
ORDER BY ratio DESC
LIMIT 5;
```

### Текстовый лог
```
[c06b4dee8f32] 2025.08.26 22:52:04.677632 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Debug> executeQuery: (from 127.0.0.1:45924, user: principalwater) (query 1, line 1) SELECT title, view_count, like_count, dislike_count, round(like_count / dislike_count, 2) AS ratio FROM otus_default.youtube WHERE (title ILIKE '%Tutorial%') AND (view_count > 1000) AND (dislike_count > 0) ORDER BY ratio DESC LIMIT 5; (stage: Complete)
[c06b4dee8f32] 2025.08.26 22:52:04.678654 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> Planner: Query to stage Complete
[c06b4dee8f32] 2025.08.26 22:52:04.678731 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> Planner: Query from stage FetchColumns to stage Complete
[c06b4dee8f32] 2025.08.26 22:52:04.678980 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> SortingStep: Adjusting memory limit before external sort with 10.73 GiB (ratio: 0.5, available system memory: 21.47 GiB)
[c06b4dee8f32] 2025.08.26 22:52:04.679135 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> Planner: Query to stage Complete
[c06b4dee8f32] 2025.08.26 22:52:04.679299 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> Planner: Query to stage WithMergeableStateAfterAggregationAndLimit only analyze
[c06b4dee8f32] 2025.08.26 22:52:04.679333 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> Planner: Query from stage FetchColumns to stage WithMergeableStateAfterAggregationAndLimit only analyze
[c06b4dee8f32] 2025.08.26 22:52:04.679417 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> SortingStep: Adjusting memory limit before external sort with 10.73 GiB (ratio: 0.5, available system memory: 21.46 GiB)
[c06b4dee8f32] 2025.08.26 22:52:04.680761 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> Planner: Query to stage WithMergeableStateAfterAggregation
[c06b4dee8f32] 2025.08.26 22:52:04.680913 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> Planner: Query from stage FetchColumns to stage WithMergeableStateAfterAggregation
[c06b4dee8f32] 2025.08.26 22:52:04.681055 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> SortingStep: Adjusting memory limit before external sort with 10.72 GiB (ratio: 0.5, available system memory: 21.44 GiB)
[c06b4dee8f32] 2025.08.26 22:52:04.681147 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> Planner: Query to stage WithMergeableStateAfterAggregationAndLimit only analyze
[c06b4dee8f32] 2025.08.26 22:52:04.681199 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> Planner: Query from stage FetchColumns to stage WithMergeableStateAfterAggregationAndLimit only analyze
[c06b4dee8f32] 2025.08.26 22:52:04.681290 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> SortingStep: Adjusting memory limit before external sort with 10.72 GiB (ratio: 0.5, available system memory: 21.44 GiB)
[c06b4dee8f32] 2025.08.26 22:52:04.681340 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> Planner: Query to stage WithMergeableStateAfterAggregationAndLimit only analyze
[c06b4dee8f32] 2025.08.26 22:52:04.681380 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> Planner: Query from stage FetchColumns to stage WithMergeableStateAfterAggregationAndLimit only analyze
[c06b4dee8f32] 2025.08.26 22:52:04.681448 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> SortingStep: Adjusting memory limit before external sort with 10.72 GiB (ratio: 0.5, available system memory: 21.44 GiB)
[c06b4dee8f32] 2025.08.26 22:52:04.681462 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> Planner: Query from stage WithMergeableStateAfterAggregationAndLimit to stage Complete
[c06b4dee8f32] 2025.08.26 22:52:04.681725 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> QueryPlanOptimizePrewhere: The min valid primary key position for moving to the tail of PREWHERE is -1
[c06b4dee8f32] 2025.08.26 22:52:04.681754 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> QueryPlanOptimizePrewhere: Moved 3 conditions to PREWHERE
[c06b4dee8f32] 2025.08.26 22:52:04.681839 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Key condition: unknown, unknown, and, unknown, and
[c06b4dee8f32] 2025.08.26 22:52:04.681923 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Filtering marks by primary and secondary keys
[c06b4dee8f32] 2025.08.26 22:52:04.682715 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): PK index has dropped 0/619 granules, it took 0ms across 7 threads.
[c06b4dee8f32] 2025.08.26 22:52:04.682800 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Query condition cache has dropped 22/619 granules for PREWHERE condition and(greater(__table1.dislike_count, 0_UInt8), greater(__table1.view_count, 1000_UInt16), ilike(__table1.title, '%Tutorial%'_String)).
[c06b4dee8f32] 2025.08.26 22:52:04.682826 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Query condition cache has dropped 0/597 granules for WHERE condition and(ilike(title, '%Tutorial%'_String), greater(view_count, 1000_UInt16), greater(dislike_count, 0_UInt8)).
[c06b4dee8f32] 2025.08.26 22:52:04.682875 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Selected 7/7 parts by partition key, 7 parts by primary key, 619/619 marks by primary key, 597 marks to read from 15 ranges
[c06b4dee8f32] 2025.08.26 22:52:04.682890 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Spreading mark ranges among streams (default reading)
[c06b4dee8f32] 2025.08.26 22:52:04.683137 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Reading approx. 4840609 rows with 8 streams
[c06b4dee8f32] 2025.08.26 22:52:04.708480 [ 897 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> Connection (clickhouse-04:9000): Sending external_roles with query: [] (0)
[c06b4dee8f32] 2025.08.26 22:52:04.710539 [ 897 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Debug> Connection (clickhouse-04:9000): Sent data for 2 scalars, total 2 rows in 0.001898834 sec., 1052 rows/sec., 68.00 B (34.96 KiB/sec.), compressed 0.4594594594594595 times to 148.00 B (76.08 KiB/sec.)
[f682e12b0e05] 2025.08.26 22:52:04.709184 [ 86 ] {e533df94-31f7-4923-b283-60eaac17efd1} <Debug> executeQuery: (from 192.168.117.5:37058, user: principalwater, initial_query_id: 3bc5b309-1433-406f-ab69-46a20e450ef8) (query 1, line 1) SELECT `__table1`.`title` AS `title`, `__table1`.`view_count` AS `view_count`, `__table1`.`like_count` AS `like_count`, `__table1`.`dislike_count` AS `dislike_count`, round(`__table1`.`like_count` / `__table1`.`dislike_count`, 2) AS `ratio` FROM `otus_default`.`youtube_local` AS `__table1` WHERE (`__table1`.`title` ILIKE '%Tutorial%') AND (`__table1`.`view_count` > 1000) AND (`__table1`.`dislike_count` > 0) ORDER BY round(`__table1`.`like_count` / `__table1`.`dislike_count`, 2) DESC LIMIT _CAST(5, 'UInt64') (stage: WithMergeableStateAfterAggregationAndLimit)
[f682e12b0e05] 2025.08.26 22:52:04.713053 [ 86 ] {e533df94-31f7-4923-b283-60eaac17efd1} <Trace> Planner: Query to stage WithMergeableStateAfterAggregationAndLimit
[f682e12b0e05] 2025.08.26 22:52:04.713184 [ 86 ] {e533df94-31f7-4923-b283-60eaac17efd1} <Trace> Planner: Query from stage FetchColumns to stage WithMergeableStateAfterAggregationAndLimit
[f682e12b0e05] 2025.08.26 22:52:04.713320 [ 86 ] {e533df94-31f7-4923-b283-60eaac17efd1} <Trace> SortingStep: Adjusting memory limit before external sort with 11.04 GiB (ratio: 0.5, available system memory: 22.09 GiB)
[f682e12b0e05] 2025.08.26 22:52:04.713471 [ 86 ] {e533df94-31f7-4923-b283-60eaac17efd1} <Trace> QueryPlanOptimizePrewhere: The min valid primary key position for moving to the tail of PREWHERE is -1
[f682e12b0e05] 2025.08.26 22:52:04.713478 [ 86 ] {e533df94-31f7-4923-b283-60eaac17efd1} <Trace> QueryPlanOptimizePrewhere: Moved 3 conditions to PREWHERE
[f682e12b0e05] 2025.08.26 22:52:04.713556 [ 86 ] {e533df94-31f7-4923-b283-60eaac17efd1} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Key condition: unknown, unknown, and, unknown, and
[f682e12b0e05] 2025.08.26 22:52:04.713611 [ 86 ] {e533df94-31f7-4923-b283-60eaac17efd1} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Filtering marks by primary and secondary keys
[f682e12b0e05] 2025.08.26 22:52:04.715927 [ 86 ] {e533df94-31f7-4923-b283-60eaac17efd1} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): PK index has dropped 0/618 granules, it took 0ms across 7 threads.
[f682e12b0e05] 2025.08.26 22:52:04.715982 [ 86 ] {e533df94-31f7-4923-b283-60eaac17efd1} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Query condition cache has dropped 28/618 granules for PREWHERE condition and(greater(__table1.dislike_count, 0_UInt8), greater(__table1.view_count, 1000_UInt16), ilike(__table1.title, '%Tutorial%'_String)).
[f682e12b0e05] 2025.08.26 22:52:04.716022 [ 86 ] {e533df94-31f7-4923-b283-60eaac17efd1} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Query condition cache has dropped 0/590 granules for WHERE condition and(ilike(title, '%Tutorial%'_String), greater(view_count, 1000_UInt16), greater(dislike_count, 0_UInt8)).
[f682e12b0e05] 2025.08.26 22:52:04.716079 [ 86 ] {e533df94-31f7-4923-b283-60eaac17efd1} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Selected 7/7 parts by partition key, 7 parts by primary key, 618/618 marks by primary key, 590 marks to read from 19 ranges
[f682e12b0e05] 2025.08.26 22:52:04.716111 [ 86 ] {e533df94-31f7-4923-b283-60eaac17efd1} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Spreading mark ranges among streams (default reading)
[f682e12b0e05] 2025.08.26 22:52:04.716349 [ 86 ] {e533df94-31f7-4923-b283-60eaac17efd1} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Reading approx. 4789183 rows with 8 streams
[c06b4dee8f32] 2025.08.26 22:52:06.083180 [ 835 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Trace> StorageDistributed (youtube): (clickhouse-04:9000) Cancelling query because enough data has been read
ATEEZ KINGDOM VOTING TUTORIAL	12223	2264	2	1132
Forrest Nolan - "Sinatra" Guitar Tutorial (Valentine\'s Day Special 2021)	9914	908	1	908
SIDRIVE IQ Fleet - Tutorial Firmware Update	4365	1593	2	796.5
Google Site Tutorial in Marathi | ROHIT ADLING	2669	760	1	760
Natural Everyday Makeup Tutorial - Full Face Makeup Tutorial - Natural Looking Makeup Tutorial  #1	1291	748	1	748
[f682e12b0e05] 2025.08.26 22:52:06.084385 [ 86 ] {e533df94-31f7-4923-b283-60eaac17efd1} <Debug> executeQuery: Read 4789183 rows, 385.72 MiB in 1.375339 sec., 3482183.6652636183 rows/sec., 280.46 MiB/sec.
[f682e12b0e05] 2025.08.26 22:52:06.084439 [ 86 ] {e533df94-31f7-4923-b283-60eaac17efd1} <Debug> MemoryTracker: Query peak memory usage: 29.47 MiB.
[c06b4dee8f32] 2025.08.26 22:52:06.086073 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Debug> executeQuery: Read 9629792 rows, 777.97 MiB in 1.40845 sec., 6837155.73857787 rows/sec., 552.36 MiB/sec.
[c06b4dee8f32] 2025.08.26 22:52:06.086120 [ 83 ] {3bc5b309-1433-406f-ab69-46a20e450ef8} <Debug> MemoryTracker: Query peak memory usage: 32.96 MiB.
```

### EXPLAIN
```
Expression (Project names)
  Limit (preliminary LIMIT (without OFFSET))
    Sorting (Merge sorted streams after aggregation stage for ORDER BY)
      Union
        Sorting (Sorting for ORDER BY)
          Expression ((Before ORDER BY + Projection))
            Expression
              ReadFromMergeTree (otus_default.youtube_local)
        ReadFromRemote (Read from remote replica)
```

## 2. Запрос с использованием первичного ключа

### SQL-запрос
```sql
SELECT
    toStartOfMonth(upload_date) AS month,
    count() AS video_count,
    sum(view_count) AS total_views,
    quantileExact(0.5)(like_count) AS median_likes
FROM otus_default.youtube
WHERE (uploader = 'T-Series')
    AND (toYear(upload_date) = 2021)
GROUP BY month
ORDER BY month;
```

### Текстовый лог
```
[c06b4dee8f32] 2025.08.26 22:52:06.559223 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Debug> executeQuery: (from 127.0.0.1:45948, user: principalwater) (query 1, line 1) SELECT toStartOfMonth(upload_date) AS month, count() AS video_count, sum(view_count) AS total_views, quantileExact(0.5)(like_count) AS median_likes FROM otus_default.youtube WHERE (uploader = 'T-Series') AND (toYear(upload_date) = 2021) GROUP BY month ORDER BY month; (stage: Complete)
[c06b4dee8f32] 2025.08.26 22:52:06.566198 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> Planner: Query to stage Complete
[c06b4dee8f32] 2025.08.26 22:52:06.566253 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> Planner: Query from stage FetchColumns to stage Complete
[c06b4dee8f32] 2025.08.26 22:52:06.566467 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> Aggregator: Adjusting memory limit before external aggregation with 11.03 GiB (ratio: 0.5, available system memory: 22.05 GiB)
[c06b4dee8f32] 2025.08.26 22:52:06.566504 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> SortingStep: Adjusting memory limit before external sort with 11.03 GiB (ratio: 0.5, available system memory: 22.05 GiB)
[c06b4dee8f32] 2025.08.26 22:52:06.566611 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> Planner: Query to stage Complete
[c06b4dee8f32] 2025.08.26 22:52:06.566733 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> Planner: Query to stage WithMergeableState only analyze
[c06b4dee8f32] 2025.08.26 22:52:06.566764 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> Planner: Query from stage FetchColumns to stage WithMergeableState only analyze
[c06b4dee8f32] 2025.08.26 22:52:06.566833 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> Aggregator: Adjusting memory limit before external aggregation with 11.03 GiB (ratio: 0.5, available system memory: 22.05 GiB)
[c06b4dee8f32] 2025.08.26 22:52:06.567060 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> Planner: Query to stage WithMergeableState
[c06b4dee8f32] 2025.08.26 22:52:06.567095 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> Planner: Query from stage FetchColumns to stage WithMergeableState
[c06b4dee8f32] 2025.08.26 22:52:06.567157 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> Aggregator: Adjusting memory limit before external aggregation with 11.03 GiB (ratio: 0.5, available system memory: 22.05 GiB)
[c06b4dee8f32] 2025.08.26 22:52:06.567243 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> Planner: Query to stage WithMergeableState only analyze
[c06b4dee8f32] 2025.08.26 22:52:06.567267 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> Planner: Query from stage FetchColumns to stage WithMergeableState only analyze
[c06b4dee8f32] 2025.08.26 22:52:06.567323 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> Aggregator: Adjusting memory limit before external aggregation with 11.03 GiB (ratio: 0.5, available system memory: 22.05 GiB)
[c06b4dee8f32] 2025.08.26 22:52:06.567358 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> Planner: Query to stage WithMergeableState only analyze
[c06b4dee8f32] 2025.08.26 22:52:06.567378 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> Planner: Query from stage FetchColumns to stage WithMergeableState only analyze
[c06b4dee8f32] 2025.08.26 22:52:06.567428 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> Aggregator: Adjusting memory limit before external aggregation with 11.03 GiB (ratio: 0.5, available system memory: 22.05 GiB)
[c06b4dee8f32] 2025.08.26 22:52:06.567441 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> Planner: Query from stage WithMergeableState to stage Complete
[c06b4dee8f32] 2025.08.26 22:52:06.567496 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> SortingStep: Adjusting memory limit before external sort with 11.03 GiB (ratio: 0.5, available system memory: 22.05 GiB)
[c06b4dee8f32] 2025.08.26 22:52:06.567598 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> QueryPlanOptimizePrewhere: The min valid primary key position for moving to the tail of PREWHERE is 1
[c06b4dee8f32] 2025.08.26 22:52:06.567604 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> QueryPlanOptimizePrewhere: Moved 3 conditions to PREWHERE
[c06b4dee8f32] 2025.08.26 22:52:06.567704 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> IInterpreterUnionOrSelectQuery: The new analyzer is enabled, but the old interpreter is used. It can be a bug, please report it. Will disable 'allow_experimental_analyzer' setting (for query: SELECT min(uploader), max(uploader), count() SETTINGS aggregate_functions_null_for_empty = false, transform_null_in = false, legacy_column_name_of_tuple_literal = false)
[c06b4dee8f32] 2025.08.26 22:52:06.567967 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Key condition: (column 0 in ['T-Series', 'T-Series']), (column 1 in [18628, +Inf)), (column 1 in (-Inf, 18992]), and, and
[c06b4dee8f32] 2025.08.26 22:52:06.574044 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Filtering marks by primary and secondary keys
[c06b4dee8f32] 2025.08.26 22:52:06.574149 [ 869 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Running binary search on index range for part all_0_5_1 (144 marks)
[c06b4dee8f32] 2025.08.26 22:52:06.574243 [ 869 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (LEFT) boundary mark: 92
[c06b4dee8f32] 2025.08.26 22:52:06.574240 [ 975 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Running binary search on index range for part all_6_11_1 (144 marks)
[c06b4dee8f32] 2025.08.26 22:52:06.574255 [ 869 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (RIGHT) boundary mark: 93
[c06b4dee8f32] 2025.08.26 22:52:06.574279 [ 869 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found continuous range in 12 steps
[c06b4dee8f32] 2025.08.26 22:52:06.574279 [ 975 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (LEFT) boundary mark: 91
[c06b4dee8f32] 2025.08.26 22:52:06.574306 [ 975 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (RIGHT) boundary mark: 92
[c06b4dee8f32] 2025.08.26 22:52:06.574312 [ 975 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found continuous range in 12 steps
[c06b4dee8f32] 2025.08.26 22:52:06.574320 [ 869 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Running binary search on index range for part all_12_17_1 (140 marks)
[c06b4dee8f32] 2025.08.26 22:52:06.574340 [ 975 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Running binary search on index range for part all_18_23_1 (141 marks)
[c06b4dee8f32] 2025.08.26 22:52:06.574339 [ 869 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (LEFT) boundary mark: 89
[c06b4dee8f32] 2025.08.26 22:52:06.574362 [ 869 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (RIGHT) boundary mark: 90
[c06b4dee8f32] 2025.08.26 22:52:06.574368 [ 869 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found continuous range in 12 steps
[c06b4dee8f32] 2025.08.26 22:52:06.574375 [ 975 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (LEFT) boundary mark: 89
[c06b4dee8f32] 2025.08.26 22:52:06.574390 [ 975 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (RIGHT) boundary mark: 90
[c06b4dee8f32] 2025.08.26 22:52:06.574394 [ 975 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found continuous range in 12 steps
[c06b4dee8f32] 2025.08.26 22:52:06.574397 [ 869 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Running binary search on index range for part all_25_25_0 (24 marks)
[c06b4dee8f32] 2025.08.26 22:52:06.574401 [ 881 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Running binary search on index range for part all_24_24_0 (25 marks)
[c06b4dee8f32] 2025.08.26 22:52:06.574424 [ 869 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (LEFT) boundary mark: 14
[c06b4dee8f32] 2025.08.26 22:52:06.574426 [ 975 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Running binary search on index range for part all_26_26_0 (8 marks)
[c06b4dee8f32] 2025.08.26 22:52:06.574428 [ 881 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (LEFT) boundary mark: 15
[c06b4dee8f32] 2025.08.26 22:52:06.574431 [ 869 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (RIGHT) boundary mark: 15
[c06b4dee8f32] 2025.08.26 22:52:06.574433 [ 975 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (LEFT) boundary mark: 3
[c06b4dee8f32] 2025.08.26 22:52:06.574438 [ 869 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found continuous range in 7 steps
[c06b4dee8f32] 2025.08.26 22:52:06.574441 [ 881 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (RIGHT) boundary mark: 16
[c06b4dee8f32] 2025.08.26 22:52:06.574446 [ 975 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (RIGHT) boundary mark: 4
[c06b4dee8f32] 2025.08.26 22:52:06.574457 [ 881 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found continuous range in 7 steps
[c06b4dee8f32] 2025.08.26 22:52:06.574456 [ 975 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found continuous range in 5 steps
[c06b4dee8f32] 2025.08.26 22:52:06.574523 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): PK index has dropped 612/619 granules, it took 0ms across 7 threads.
[c06b4dee8f32] 2025.08.26 22:52:06.587141 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Query condition cache has dropped 7/7 granules for PREWHERE condition and(greaterOrEquals(__table1.upload_date, '2021-01-01'_String), less(__table1.upload_date, '2022-01-01'_String), equals(__table1.uploader, 'T-Series'_String)).
[c06b4dee8f32] 2025.08.26 22:52:06.598290 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Query condition cache has dropped 0/0 granules for WHERE condition and(equals(uploader, 'T-Series'_String), and(greaterOrEquals(upload_date, '2021-01-01'_String), less(upload_date, '2022-01-01'_String))).
[c06b4dee8f32] 2025.08.26 22:52:06.606869 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Selected 7/7 parts by partition key, 0 parts by primary key, 7/619 marks by primary key, 0 marks to read from 0 ranges
[c06b4dee8f32] 2025.08.26 22:52:06.609598 [ 740 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> AggregatingTransform: Aggregated. 0 to 0 rows (from 0.00 B) in 0.002534208 sec. (0.000 rows/sec., 0.00 B/sec.)
[c06b4dee8f32] 2025.08.26 22:52:06.609666 [ 740 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> Aggregator: Merging aggregated data
[c06b4dee8f32] 2025.08.26 22:52:06.610220 [ 740 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> Connection (clickhouse-04:9000): Sending external_roles with query: [] (0)
[c06b4dee8f32] 2025.08.26 22:52:06.610870 [ 740 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Debug> Connection (clickhouse-04:9000): Sent data for 2 scalars, total 2 rows in 0.000580417 sec., 3444 rows/sec., 68.00 B (114.35 KiB/sec.), compressed 0.4594594594594595 times to 148.00 B (248.87 KiB/sec.)
[f682e12b0e05] 2025.08.26 22:52:06.610735 [ 86 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Debug> executeQuery: (from 192.168.117.5:37058, user: principalwater, initial_query_id: 639fdb97-388b-4f13-b5e7-ee9a63866cd7) (query 1, line 1) SELECT toStartOfMonth(`__table1`.`upload_date`) AS `month`, count() AS `video_count`, sum(`__table1`.`view_count`) AS `total_views`, quantileExact(0.5)(`__table1`.`like_count`) AS `median_likes` FROM `otus_default`.`youtube_local` AS `__table1` WHERE (`__table1`.`uploader` = 'T-Series') AND ((`__table1`.`upload_date` >= '2021-01-01') AND (`__table1`.`upload_date` < '2022-01-01')) GROUP BY toStartOfMonth(`__table1`.`upload_date`) ORDER BY toStartOfMonth(`__table1`.`upload_date`) ASC (stage: WithMergeableState)
[f682e12b0e05] 2025.08.26 22:52:06.614474 [ 86 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> Planner: Query to stage WithMergeableState
[f682e12b0e05] 2025.08.26 22:52:06.614542 [ 86 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> Planner: Query from stage FetchColumns to stage WithMergeableState
[f682e12b0e05] 2025.08.26 22:52:06.614712 [ 86 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> Aggregator: Adjusting memory limit before external aggregation with 11.04 GiB (ratio: 0.5, available system memory: 22.08 GiB)
[f682e12b0e05] 2025.08.26 22:52:06.614896 [ 86 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> QueryPlanOptimizePrewhere: The min valid primary key position for moving to the tail of PREWHERE is 1
[f682e12b0e05] 2025.08.26 22:52:06.614903 [ 86 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> QueryPlanOptimizePrewhere: Moved 3 conditions to PREWHERE
[f682e12b0e05] 2025.08.26 22:52:06.615046 [ 86 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> IInterpreterUnionOrSelectQuery: The new analyzer is enabled, but the old interpreter is used. It can be a bug, please report it. Will disable 'allow_experimental_analyzer' setting (for query: SELECT min(uploader), max(uploader), count() SETTINGS aggregate_functions_null_for_empty = false, transform_null_in = false, legacy_column_name_of_tuple_literal = false)
[f682e12b0e05] 2025.08.26 22:52:06.615330 [ 86 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Key condition: (column 0 in ['T-Series', 'T-Series']), (column 1 in [18628, +Inf)), (column 1 in (-Inf, 18992]), and, and
[f682e12b0e05] 2025.08.26 22:52:06.615363 [ 86 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Filtering marks by primary and secondary keys
[f682e12b0e05] 2025.08.26 22:52:06.617528 [ 864 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Running binary search on index range for part all_0_5_1 (144 marks)
[f682e12b0e05] 2025.08.26 22:52:06.617553 [ 864 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (LEFT) boundary mark: 92
[f682e12b0e05] 2025.08.26 22:52:06.617573 [ 864 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (RIGHT) boundary mark: 93
[f682e12b0e05] 2025.08.26 22:52:06.617581 [ 864 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found continuous range in 12 steps
[f682e12b0e05] 2025.08.26 22:52:06.617680 [ 756 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Running binary search on index range for part all_6_11_1 (143 marks)
[f682e12b0e05] 2025.08.26 22:52:06.617706 [ 756 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (LEFT) boundary mark: 91
[f682e12b0e05] 2025.08.26 22:52:06.617716 [ 756 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (RIGHT) boundary mark: 92
[f682e12b0e05] 2025.08.26 22:52:06.617734 [ 756 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found continuous range in 12 steps
[f682e12b0e05] 2025.08.26 22:52:06.617799 [ 834 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Running binary search on index range for part all_12_17_1 (140 marks)
[f682e12b0e05] 2025.08.26 22:52:06.617821 [ 834 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (LEFT) boundary mark: 89
[f682e12b0e05] 2025.08.26 22:52:06.617830 [ 834 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (RIGHT) boundary mark: 90
[f682e12b0e05] 2025.08.26 22:52:06.617838 [ 834 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found continuous range in 12 steps
[f682e12b0e05] 2025.08.26 22:52:06.617879 [ 834 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Running binary search on index range for part all_18_23_1 (141 marks)
[f682e12b0e05] 2025.08.26 22:52:06.617900 [ 834 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (LEFT) boundary mark: 89
[f682e12b0e05] 2025.08.26 22:52:06.617916 [ 834 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (RIGHT) boundary mark: 90
[f682e12b0e05] 2025.08.26 22:52:06.617924 [ 834 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found continuous range in 12 steps
[f682e12b0e05] 2025.08.26 22:52:06.617974 [ 864 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Running binary search on index range for part all_24_24_0 (25 marks)
[f682e12b0e05] 2025.08.26 22:52:06.617989 [ 864 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (LEFT) boundary mark: 15
[f682e12b0e05] 2025.08.26 22:52:06.617994 [ 864 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (RIGHT) boundary mark: 16
[f682e12b0e05] 2025.08.26 22:52:06.617998 [ 864 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found continuous range in 7 steps
[f682e12b0e05] 2025.08.26 22:52:06.618011 [ 864 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Running binary search on index range for part all_25_25_0 (24 marks)
[f682e12b0e05] 2025.08.26 22:52:06.618025 [ 864 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (LEFT) boundary mark: 14
[f682e12b0e05] 2025.08.26 22:52:06.618030 [ 864 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (RIGHT) boundary mark: 15
[f682e12b0e05] 2025.08.26 22:52:06.618033 [ 864 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found continuous range in 7 steps
[f682e12b0e05] 2025.08.26 22:52:06.618062 [ 756 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Running binary search on index range for part all_26_26_0 (8 marks)
[f682e12b0e05] 2025.08.26 22:52:06.618069 [ 756 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (LEFT) boundary mark: 3
[f682e12b0e05] 2025.08.26 22:52:06.618079 [ 756 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found (RIGHT) boundary mark: 4
[f682e12b0e05] 2025.08.26 22:52:06.618089 [ 756 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Found continuous range in 5 steps
[f682e12b0e05] 2025.08.26 22:52:06.618132 [ 86 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): PK index has dropped 611/618 granules, it took 0ms across 7 threads.
[f682e12b0e05] 2025.08.26 22:52:06.618182 [ 86 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Query condition cache has dropped 5/7 granules for PREWHERE condition and(greaterOrEquals(__table1.upload_date, '2021-01-01'_String), less(__table1.upload_date, '2022-01-01'_String), equals(__table1.uploader, 'T-Series'_String)).
[f682e12b0e05] 2025.08.26 22:52:06.618204 [ 86 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Query condition cache has dropped 0/2 granules for WHERE condition and(equals(uploader, 'T-Series'_String), and(greaterOrEquals(upload_date, '2021-01-01'_String), less(upload_date, '2022-01-01'_String))).
[f682e12b0e05] 2025.08.26 22:52:06.618218 [ 86 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Selected 7/7 parts by partition key, 2 parts by primary key, 7/618 marks by primary key, 2 marks to read from 2 ranges
[f682e12b0e05] 2025.08.26 22:52:06.618231 [ 86 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Spreading mark ranges among streams (default reading)
[f682e12b0e05] 2025.08.26 22:52:06.618342 [ 86 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Debug> otus_default.youtube_local (4f28bcfb-7274-4cd1-b0e7-312eeb9653b1) (SelectExecutor): Reading approx. 16384 rows with 2 streams
[f682e12b0e05] 2025.08.26 22:52:06.623293 [ 780 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> AggregatingTransform: Aggregating
[f682e12b0e05] 2025.08.26 22:52:06.623343 [ 780 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> HashTablesStatistics: An entry for key=5274391152256242291 found in cache: sum_of_sizes=3, median_size=2
[f682e12b0e05] 2025.08.26 22:52:06.623363 [ 780 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> Aggregator: Aggregation method: key16
[f682e12b0e05] 2025.08.26 22:52:06.623476 [ 780 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> AggregatingTransform: Aggregated. 2 to 2 rows (from 36.00 B) in 0.005016333 sec. (398.698 rows/sec., 7.01 KiB/sec.)
[f682e12b0e05] 2025.08.26 22:52:06.624385 [ 874 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> AggregatingTransform: Aggregating
[f682e12b0e05] 2025.08.26 22:52:06.624390 [ 874 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> HashTablesStatistics: An entry for key=5274391152256242291 found in cache: sum_of_sizes=3, median_size=2
[f682e12b0e05] 2025.08.26 22:52:06.624404 [ 874 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> Aggregator: Aggregation method: key16
[f682e12b0e05] 2025.08.26 22:52:06.624451 [ 874 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> AggregatingTransform: Aggregated. 1 to 1 rows (from 18.00 B) in 0.005990792 sec. (166.923 rows/sec., 2.93 KiB/sec.)
[f682e12b0e05] 2025.08.26 22:52:06.624455 [ 874 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Trace> Aggregator: Merging aggregated data
[f682e12b0e05] 2025.08.26 22:52:06.625113 [ 86 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Debug> executeQuery: Read 16384 rows, 472.91 KiB in 0.014596 sec., 1122499.3148807893 rows/sec., 31.64 MiB/sec.
[f682e12b0e05] 2025.08.26 22:52:06.625277 [ 86 ] {48148bd7-f940-42d6-9c04-238b694be97e} <Debug> MemoryTracker: Query peak memory usage: 1.29 MiB.
[c06b4dee8f32] 2025.08.26 22:52:06.625521 [ 740 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Trace> Aggregator: Merging partially aggregated blocks (bucket = -1).
[c06b4dee8f32] 2025.08.26 22:52:06.625588 [ 740 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Debug> Aggregator: Merged partially aggregated blocks for bucket #-1. Got 3 rows, 78.00 B from 3 source rows in 5.2833e-05 sec. (56782.693 rows/sec., 1.41 MiB/sec.)
2021-03-01	1	271190	6661
2021-05-01	1	54671	651
2021-09-01	1	4382737	37525
[c06b4dee8f32] 2025.08.26 22:52:06.626639 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Debug> executeQuery: Read 16384 rows, 472.91 KiB in 0.067481 sec., 242794.26801618232 rows/sec., 6.84 MiB/sec.
[c06b4dee8f32] 2025.08.26 22:52:06.626668 [ 83 ] {639fdb97-388b-4f13-b5e7-ee9a63866cd7} <Debug> MemoryTracker: Query peak memory usage: 1.66 MiB.
```

### EXPLAIN
```
Expression (Project names)
  Sorting (Sorting for ORDER BY)
    Expression ((Before ORDER BY + Projection))
      MergingAggregated
        Union
          Aggregating
            Expression (Before GROUP BY)
              Expression
                ReadFromMergeTree (otus_default.youtube_local)
          ReadFromRemote (Read from remote replica)
```
