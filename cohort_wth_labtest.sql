WITH co AS
(
SELECT icu.subject_id, icu.hadm_id, icu.icustay_id, FIRST_CAREUNIT, pat.gender
, EXTRACT(EPOCH FROM outtime - intime)/60.0/60.0/24.0 as icu_length_of_stay
, EXTRACT('epoch' from icu.intime - pat.dob) / 60.0 / 60.0 / 24.0 / 365.242 as age
, RANK() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS icustay_id_order
, CASE
    WHEN ICU.FIRST_CAREUNIT = 'MICU' THEN 0
    ELSE 1 END
    AS exclusion_1st_care_unit
FROM icustays icu
INNER JOIN patients pat
  ON icu.subject_id = pat.subject_id
)
---------------------------
, serv AS
(
SELECT icu.hadm_id, icu.icustay_id, se.curr_service
, CASE
    WHEN curr_service like '%SURG' then 1
    WHEN curr_service = 'ORTHO' then 1
    ELSE 0 END
  as surgical
, RANK() OVER (PARTITION BY icu.hadm_id ORDER BY se.transfertime DESC) as rank
FROM icustays icu
LEFT JOIN services se
 ON icu.hadm_id = se.hadm_id
AND se.transfertime < icu.intime + interval '12' hour
)
---------------------------
, icd9 as(
  SELECT diag.hadm_id,diag.icd9_code
  , CASE 
      WHEN
      ( diag.icd9_code != 'None'
      AND
        substring(diag.icd9_code,1,3) IN ('200', '201', '202', '203', '204', '205', '206', '207', '208')
       )
    THEN 1
    ELSE 0 END
    AS HM
  FROM DIAGNOSES_ICD as diag
  inner join  D_ICD_DIAGNOSES 
  on diag.icd9_code= D_ICD_DIAGNOSES.icd9_code
)
---------------------------

,final_co as (
   select 
    co.subject_id, co.hadm_id, co.icustay_id,co.age, co.gender, co.icustay_id_order, co.icu_length_of_stay,
    icd9.icd9_code,
    exclusion_1st_care_unit
  , CASE
        WHEN co.icu_length_of_stay < 1 then 1
    ELSE 0 END
    AS exclusion_los
  , CASE
        WHEN co.age < 16 then 1
    ELSE 0 END
    AS exclusion_age
  , CASE 
        WHEN co.icustay_id_order != 1 THEN 1
    ELSE 0 END 
    AS exclusion_first_stay
  , CASE
        WHEN serv.surgical = 1 THEN 1
    ELSE 0 END
    as exclusion_surgical 
    
   FROM co
   INNER JOIN serv
    ON  co.icustay_id = serv.icustay_id
    AND serv.rank = 1
   INNER join icd9
    on  co.hadm_id=icd9.hadm_id
    AND HM = 1  
),
----------------
RBC as (
 select subject_id, hadm_id, icustay_id, itemid as RBC_itemid
  from inputevents_mv
  where(itemid in (225168,226368) AND amount>0 )
  
  UNION ALL

  select subject_id, hadm_id, icustay_id,itemid as RBC_itemid
  from inputevents_cv
  where (itemid in (30001,30104) AND amount>0 )
)

------------------
, platelet as (
   select subject_id, hadm_id, icustay_id, itemid as platelet_itemid
   from inputevents_mv
   where (itemid in (225170,226369) AND amount>0 )
   
   UNION ALL
   
   select subject_id, hadm_id, icustay_id,itemid as platelet_itemid
   from inputevents_cv
   where (itemid = 30006 AND amount>0 )
)

----------------
, positive_blood_result as (

  select subject_id, hadm_id,
  max (case when (org_itemid is null AND ab_itemid is null) THEN 1 ELSE 0 END ) as p_blood_culture_1
  from microbiologyevents
  where (spec_type_desc = 'BLOOD CULTURE')
  GROUP BY subject_id, hadm_id

)
----------------
 , RBC_result as (
   select subject_id, hadm_id, icustay_id,
   max(CASE WHEN RBC.RBC_itemid >0 then 1 ELSE 0 END)as RBC_1
   from RBC
   GROUP BY subject_id, hadm_id, icustay_id
  )
----------------
, platelet_result as (
   select subject_id, hadm_id, icustay_id,
   max(CASE WHEN platelet.platelet_itemid >0 then 1 ELSE 0 END)as platelet_1
   from platelet
   GROUP BY subject_id, hadm_id, icustay_id
   ORDER BY subject_id, hadm_id, icustay_id
)
----------------
,  VASOPRESSORDURATIONS_result as (
   select icustay_id
   ,max(CASE WHEN VASOPRESSORDURATIONS.duration_hours>0 then 1 ELSE 0 END) as vasopressor_1 
   from VASOPRESSORDURATIONS
   GROUP BY icustay_id
   ORDER BY icustay_id
)
----------------
, ventdurations_result as (
  select icustay_id
  ,max(CASE WHEN ventdurations.duration_hours>0 then 1 ELSE 0 END) as ventilation_1
  from ventdurations
  GROUP BY icustay_id
  ORDER BY icustay_id
)
----------------
, AST_result as (
   select subject_id, hadm_id, icustay_id, 
   max (ast) as AST
   from siqi_AST_ALT
   where ast is not null
   group by subject_id, hadm_id, icustay_id
   order by subject_id, hadm_id, icustay_id
)
----------------
, ALT_result as (
  select subject_id, hadm_id, icustay_id, 
  max (ALT) as ALT
  from siqi_AST_ALT
  where ALT is not null
  group by subject_id, hadm_id, icustay_id
  order by subject_id, hadm_id, icustay_id
)
----------------
, finalco_wth_score_n_exclusion as (
  select 
  final_co.subject_id, final_co.hadm_id, final_co.icustay_id
  
  ---AST, ALT
  , AST_RESULT.AST
  , ALT_RESULT.ALT
  
  ---Renal replacement therapy
  , siqi_rrt.rrt as RRT
  
  ---SOFA score
  , SOFA.sofa
  
  ---postive blood test
  , positive_blood_result.p_blood_culture_1
  
  ---Red blood cell transfusion
  , RBC_result.RBC_1
  
  ---Platelet transfusion
  ,platelet_result.platelet_1
   
  ---patient with vesopressor service
  , VASOPRESSORDURATIONS_result.vasopressor_1
 
  
  ---patient with mechanical ventilation service
  , ventdurations_result.ventilation_1
 
   
  ,final_co.age, final_co.gender, final_co.icu_length_of_stay, final_co.icd9_code

  FROM final_co
  left join SOFA
  on final_co.hadm_id = SOFA.hadm_id
  AND final_co.icustay_id=SOFA.icustay_id
  AND final_co.subject_id=SOFA.subject_id
  
  left join siqi_rrt
  on final_co.hadm_id = siqi_rrt.hadm_id
  AND final_co.icustay_id=siqi_rrt.icustay_id
  AND final_co.subject_id=siqi_rrt.subject_id
  
  left join AST_RESULT
  on  final_co.hadm_id = AST_RESULT.hadm_id
  AND final_co.icustay_id=AST_RESULT.icustay_id
  AND final_co.subject_id=AST_RESULT.subject_id
  
  left join ALT_RESULT
  on  final_co.hadm_id = ALT_RESULT.hadm_id
  AND final_co.icustay_id=ALT_RESULT.icustay_id
  AND final_co.subject_id=ALT_RESULT.subject_id
  
  left join positive_blood_result
  on  final_co.hadm_id = positive_blood_result.hadm_id
  AND final_co.subject_id=positive_blood_result.subject_id
  
  left join platelet_result
   on  final_co.hadm_id = platelet_result.hadm_id
  AND final_co.icustay_id=platelet_result.icustay_id
  AND final_co.subject_id=platelet_result.subject_id
  
  left join RBC_result
   on  final_co.hadm_id = RBC_result.hadm_id
  AND final_co.icustay_id=RBC_result.icustay_id
  AND final_co.subject_id=RBC_result.subject_id
  
  left join VASOPRESSORDURATIONS_result
  on final_co.icustay_id=VASOPRESSORDURATIONS_result.icustay_id
  
  left join ventdurations_result
  on final_co.icustay_id=ventdurations_result.icustay_id
  
 where 
  exclusion_1st_care_unit = 0
  --AND exclusion_los = 0
  AND exclusion_age = 0
  AND exclusion_first_stay = 0
  --AND exclusion_surgical = 0
  
 ) 
----------------
  select HM_lab_test.*, finalco_wth_score_n_exclusion.*
  
  FROM finalco_wth_score_n_exclusion
  left join 
  HM_lab_test
  
  on  HM_lab_test.hadm_id = finalco_wth_score_n_exclusion.hadm_id
  AND HM_lab_test.icustay_id = finalco_wth_score_n_exclusion.icustay_id
  AND HM_lab_test.subject_id = finalco_wth_score_n_exclusion.subject_id
  AND HM_lab_test.lab_test_rank=1
 
