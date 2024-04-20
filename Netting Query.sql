/*=======================================
Create Tables
=======================================*/

create table charities (charity_name varchar(255), approval_status varchar(1));
create table donations (time_stamp datetime, donor varchar(255), donation_amt float, candidate varchar(255), charity varchar(255));
create table users (email varchar(255), full_name varchar(255));
create table netted_donations (donation_timestamp datetime, netting_timestamp datetime, donor varchar(255), charity varchar(255), netted_amt float, candidate varchar(255));

/*=======================================
Netting Query
	Tables: Users, Charities, Donations, Netted_Donations
    After: run the "process expired donations" query
=======================================*/

/*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Step 1: Sum each side
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*/

DROP TEMPORARY TABLE IF EXISTS donation_totals;
CREATE TEMPORARY TABLE donation_totals as
select			sum(donation_amt) as donation_total
				,candidate
from			donations 
group by		candidate;

/*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Step 2: Runsum the bigger side (future improvement: could stop once we get to the marginal donation)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*/

SET @bigger_side := (SELECT candidate FROM donation_totals ORDER BY donation_total DESC LIMIT 1);

DROP TEMPORARY TABLE IF EXISTS constrained_runsum;
CREATE TEMPORARY TABLE constrained_runsum as
select			SUM(donation_amt) over (order by time_stamp desc) as RS_Donation
				,donor
                ,time_stamp
                ,charity
                ,donation_amt
from			donations
where			candidate = @bigger_side;

/*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Step 3: Find the marginal donation
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*/

SET @cutoff := (select sum(donation_amt) from donations where candidate <> @bigger_side);
SET @marginal_rs := (select min(rs_donation) from rs_donation where rs_donation >= @cutoff);


/*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Step 4: Process the smaller side
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*/

insert into netted_donations
select			time_stamp as donation_timestamp
				,now() as netting_timestamp
                ,donor
                ,charity
                ,donation_amt as netted_amt
                ,candidate
from			donations
where			candidate <> @bigger_side;

delete			
from			donations
where			candidate <> @bigger_side;

set @netting_timestamp := (select now());


/*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Step 5: process everything below the marginal donation on the bigger side
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*/

insert into netted_donations
select			time_stamp as donation_timestamp
				,@netting_timestamp as netting_timestamp
                ,donor
                ,charity
                ,donation_amt as netted_amt
                ,candidate
from			constrained_runsum
where			candidate = @bigger_side
and				rs_donation < @cutoff;

delete			d
from			donations d
join			constrained_runsum cr
	on d.candidate = cr.candidate
    and d.time_stamp = cr.time_stamp
    and d.donor = cr.donor
    and d.donation_amt = cr.donation_amt
where			d.candidate = @bigger_side
and				cr.rs_donation < @cutoff;


/*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Step 6: process everything below the marginal donation on the bigger side
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*/
SET @marginal_remaining := @marginal_rs - @cutoff;
SET @marginal_netted_amt := (select donation_amt 
							from donations 
                            where candidate = @bigger_side
                            and rs_donation = @marginal_rs) - @marginal_remaining;
                            

insert into netted_donations
select			time_stamp as donation_timestamp
				,@netting_timestamp as netting_timestamp
                ,donor
                ,charity
                ,@marginal_netted_amt as netted_amt
                ,candidate
from			donations
where			candidate = @bigger_side
and				rs_donation = @marginal_rs;

update 			donations d
join			constrained_runsum cr
	on d.candidate = cr.candidate
    and d.time_stamp = cr.time_stamp
    and d.donor = cr.donor
    and d.donation_amt = cr.donation_amt
set				d.donation_amt = @marginal_remaining
where			d.candidate = @bigger_side
and				cr.rs_donation = @marginal_rs
