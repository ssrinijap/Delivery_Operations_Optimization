# create new schema and fix that schema
CREATE SCHEMA stemstore;
Use Stemstore;
SELECT * FROM ofd_sheet;
ALTER table ofd_sheet
CHANGE Column ï»¿Out_for_delivery_date Out_for_delivery_date text;
SELECT * FROM offline_products_table;
ALTER table offline_products_table
CHANGE Column ï»¿awb_shipment_number awb_shipment_number text;
SELECT * FROM online_products_table;
ALTER table online_products_table
CHANGE Column ï»¿awb_nr awb_shipment_number text;
SELECT * FROM order_table;
ALTER table order_table
CHANGE Column ï»¿awb_shipment_number awb_shipment_number text;
SELECT * FROM vendor_rate_card;
ALTER table vendor_rate_card
CHANGE Column ï»¿Vendor_ID Vendor_ID text;
SELECT * FROM fleet_table;
ALTER table fleet_table
CHANGE Column ï»¿Driver_ID Driver_ID text;

#change datatype of Date columns from str to DATE in ofd_sheet
UPDATE ofd_sheet
SET out_for_delivery_date = str_to_date(out_for_delivery_date,'%d-%m-%Y');
ALTER table ofd_sheet
MODIFY COLUMN out_for_delivery_date DATE;
UPDATE ofd_sheet
SET promised_delivery_date = str_to_date(promised_delivery_date,'%d-%m-%Y');
ALTER table ofd_sheet
MODIFY COLUMN Promised_Delivery_date DATE;

#Main Query
#Calculating difference between current and revised rates and leadtimes
select *, (Q.average_lead_time-Q.average_revised_lead_time) as Reduction_in_delay,
(Q.average_current_cost-Q.average_revised_cost) as Reduction_in_cost from 
#Q-Table -- Inner joining M table with N table on city_id to get top 10 city's by low CDSI's and their current average & revised leadtimes and costs
(select M.*, N.Average_current_cost, N.Average_lead_time, N.Average_revised_lead_time, N.Average_revised_cost From 
#M-table -- Innner joining D & B tables by city ID's to get average delays and average CDSI's for top 10 cities with lowest CDSI's
(SELECT D.City_name, D.city_id, D.AVG_CDSI, B.average_delay from (
# D-table --Calculating Average CDSI by joining ofd_sheet with order table to get CDSI at Shipment level and grouping by city_id's
(select C.city_name, C.city_ID, AVG(C.CDSI) as AVG_CDSI FROM 
(SELECT O.city_name,O.city_ID,O.awb_shipment_number,T.CDSI 
FROM ofd_sheet O inner join order_table T ON O.awb_shipment_number = T.awb_shipment_number) as C
group by C.city_name, C.city_ID
order by avg(C.CDSI)) as D
inner join
# B-table --Calculating Average delay by city_id's
(select A.city_id,A.city_name,avg(A.Delay) as average_delay from 
(select *, datediff(out_for_delivery_date,Promised_Delivery_date) as Delay 
from ofd_sheet) as A
group by city_id,city_name
order by avg(A.delay) DESC
)  B on D.city_ID = B.city_ID)
ORDER BY AVG_CDSI ASC
limit 10) M inner join 
#N-Table-- Calculating averages of rates and delivery_lead_timesfor current vendors and revised vendors
(select L.city_id,L.city_name,avg(L.current_cost) as Average_current_cost,avg(L.current_lead_time) as Average_lead_time,
avg(L.revised_lead_time) as Average_revised_lead_time,avg(L.revised_rate) as Average_revised_cost from (
#L=Table-- Joining J table with K table on weight bucket to get vendors with minimum rate and lead time by condition rank as 1
SELECT J.*, K.vendor_ID as revised_vendor,K.Delivery_Lead_Time as Revised_lead_time,K.Rate_per_shipment as revised_rate from 
# K-table--Ranking vendor_rate_card table for each weight bucket to extract vendor_id's with minimum lead time and cost for a given bucket
(select v.Weight_Buckets,v.vendor_id,v.Rate_per_shipment,v.Delivery_Lead_Time,
RANK() OVER(PARTITION BY v.Weight_Buckets order by v.Delivery_Lead_Time ASC, v.Rate_per_shipment ASC) as Rnk
from vendor_rate_card v) K
inner join
#J Table- Joining H table with vendor_rate_card table by concatenation of vendor_id and weight_bucket to get current cost & leaad time
(SELECT H.*, v.Rate_per_shipment as current_cost,v.Delivery_Lead_Time as current_lead_time from
#H Table- Joining with fleet table by driver_id to get current vendor 
(SELECT G.*, f.vendor_ID as current_vendor from 
#G Table --Pivoting vendor_id column in E table by rates and delivery_lead_times
(SELECT E.awb_shipment_number,E.city_id,E.city_name,E.Driver_ID,E.SKU_CODE,E.weight_Bucket,E.weight,
max(case when vendor_id = 'VEN-5000' then Rate_per_shipment END) as VEN_5000_rate_per_shipment,
max(case when vendor_id = 'VEN-5000' then Delivery_Lead_time END) as VEN_5000_delivery_lead_time,
max(case when vendor_id = 'VEN-4000' then Rate_per_shipment END) as VEN_4000_rate_per_shipment,
max(case when vendor_id = 'VEN-4000' then Delivery_Lead_time END) as VEN_4000_delivery_lead_time,
max(case when vendor_id = 'VEN-3000' then Rate_per_shipment END) as VEN_3000_rate_per_shipment,
max(case when vendor_id = 'VEN-3000' then Delivery_Lead_time END) as VEN_3000_delivery_lead_time,
max(case when vendor_id = 'VEN-2000' then Rate_per_shipment END) as VEN_2000_rate_per_shipment,
max(case when vendor_id = 'VEN-2000' then Delivery_Lead_time END) as VEN_2000_delivery_lead_time,
max(case when vendor_id = 'VEN-1000' then Rate_per_shipment END) as VEN_1000_rate_per_shipment,
max(case when vendor_id = 'VEN-1000' then Delivery_Lead_time END) as VEN_1000_delivery_lead_time
FROM 
#E Table--Join OFD table with offline_products_table and vendor_rate_card based on weight buckets for shipment, 
# extracting various vendors and their corresponding rates for each shipment and weight bucket
(SELECT s.awb_shipment_number,s.city_id,s.city_name,s.Driver_ID,s.SKU_CODE,left(p.volumetric_weight,1) as weight_bucket,p.weight,v.Rate_per_shipment,v.Delivery_Lead_Time,v.Vendor_Id,v.Vendor_Name 
from ofd_sheet s left join offline_products_table p
on s.SKU_CODE = p.SKU_CODE left join fleet_table f on f.Driver_ID = s.Driver_ID left join vendor_rate_card v on 
left(p.volumetric_weight,1)= v.weight_buckets) E
GROUP BY E.awb_shipment_number,E.city_id,E.city_name,E.Driver_ID,E.SKU_CODE,E.Weight_Bucket,E.weight) G
inner join fleet_table f on G.Driver_ID= f.Driver_ID) H 
inner join vendor_rate_card v on concat(H.current_vendor, H.weight_bucket) = concat(v.vendor_ID,v.weight_buckets)) J
on J.weight_bucket = K.weight_buckets
where rnk = 1) L 
group by L.city_id,L.city_name) N on M.city_id = N.city_id) Q;




