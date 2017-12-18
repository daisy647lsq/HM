DROP MATERIALIZED VIEW IF EXISTS siqi_AST_ALT CASCADE;
CREATE MATERIALIZED VIEW siqi_AST_ALT AS
with AST as (
select subject_id, hadm_id, icustay_id, itemid, charttime, valuenum
from chartevents
where itemid in (769,770,220587,220644)
)

, ranked1 as (
 select AST.*, dense_rank() over( 
 PARTITION BY
 AST.subject_id, AST.hadm_id,AST.icustay_id,AST.ITEMID 
 
 ORDER BY ABS(EXTRACT('epoch' from ie.intime-AST.charttime)))
from AST inner join icustays ie
 on AST.subject_id = ie.subject_id
 AND AST.hadm_id = ie.hadm_id
 AND AST.icustay_id = ie.icustay_id
)


select subject_id, hadm_id, icustay_id, itemid,
max(case when itemid=769 or itemid=220587 then valuenum else null end) as AST,
max(case when itemid=770 or itemid=220644 then valuenum else null end) as ALT
from ranked1
where dense_rank=1
GROUP BY subject_id, hadm_id, icustay_id, itemid