DROP MATERIALIZED VIEW IF EXISTS siqi_vital_signs CASCADE;
CREATE MATERIALIZED VIEW siqi_vital_signs AS
with vital_sign as(
  select ce.subject_id, ce.hadm_id, ce.icustay_id, ce.itemid, ce.valuenum,
  DENSE_RANK() OVER (PARTITION BY ce.subject_id, ce.hadm_id, ce.icustay_id, ce.itemid
  ORDER BY ABS(EXTRACT('epoch' from ie.intime-ce.charttime))) AS v_rank
  from icustays ie
  left join chartevents ce
  on ie.hadm_id = ce.hadm_id
  AND ie.icustay_id = ce.icustay_id
  AND ie.subject_id = ce.subject_id
  
  where itemid in ('223761', '678'
                  ,'220179','220180','220181'
                  ,'220050','220051','220052'
                  ,'3313', '3312', '8502'
                  , '51', '52','8368'
                  ,'220045', '211'
                  ,'220210','618','3603')
  )
  

  select subject_id, hadm_id, icustay_id,

  max (case when itemid = 223761 then valuenum 
            when itemid = 678 then valuenum ELSE NULL END) as temperature,
  
  max (case when itemid = 220210 then valuenum 
            when itemid = 618 then valuenum 
            when itemid = 3603 then valuenum ELSE NULL END) as respiration,
  
  max (case when itemid = 220045 then valuenum 
            when itemid = 211 then valuenum ELSE NULL END) as heart_rate,

  max (case when itemid = 220179 then valuenum 
            when itemid = 220050 then valuenum 
            when itemid = 51 then valuenum
            when itemid = 3313 then valuenum ELSE NULL END) as arterial_BP_systolic,
  
  max (case when itemid = 220180 then valuenum 
            when itemid = 220051 then valuenum 
            when itemid = 8502 then valuenum 
            when itemid = 8368 then valuenum ELSE NULL END) as arterial_BP_diastolic,
 
  max (case when itemid = 220181 then valuenum 
            when itemid = 220052 then valuenum
            when itemid = 52 then valuenum
            when itemid = 3312 then valuenum ELSE NULL END) as arterial_BP_mean
  
  from vital_sign
  where v_rank=1
  group by subject_id, hadm_id, icustay_id
  order by subject_id, hadm_id, icustay_id;
  