{{ config(materialized='table',
   tags=['strategy_planning']) }}

with salesforce_data as (

    select distinct
        opportunity_id_case_safe,
        type as opportunity_type,
        stage,
        close_date
    from {{ ref('stg_sandpodsdbo__cmosalesforcedata__hist') }}

),

dealdashboardv2 as (

    select * from {{ ref('stg_sandpodsdbo__dealdashboardv2__hist') }}

),

pricingprodlist as (

    select * from {{ ref('stg_sandpodsdbo__pricingprodlist__hist') }}

),

raw_joins as (

    select
        v2.productid,
        v2.dealid,
        v2.originaldealid,
        v2.active,
        v2.mainopportunity,
        v2.accountname,
        v2.dealdescription,
        v2.rundate,
        v2.intakesheetreceived,
        v2.intakesheetfinalized,
        v2.spvalidationcomplete,
        v2.intakesheetconsumedandpalapplied,
        v2.buproductreversestagingpopulated,
        v2.spmanualreviewofpaloutput,
        v2.tatcommunicatedtoliaison,
        v2.buoutputgenerated,
        v2.buoutputemailed,
        v2.spreceivesandvalidatesbuoutput,
        v2.allproductpricingdeterminationscomplete,
        v2.communicationtoliaisonwithfinalpricing,
        v2.sschallengebualternatepricing,
        v2.challengemeeting,
        v2.buoutputformupdatedwithchallengeoutcome,
        v2.dealcomplete,
        v2.tatactual,
        v2.tatrequested,
        v2.renewalleadtime,
        v2.dealstage,
        v2.salesexecutive,
        v2.clientservicesexecutive,
        v2.submittor,
        v2.resubmissionreason,
        v2.accounttype,
        v2.accountmotivation,
        v2.accounthealth,
        v2.accounthealthexplanation,
        v2.accountsegment,
        v2.accountbudget,
        v2.accountbudgetyear,
        v2.clientbuyingmotivation,
        v2.pointofcontactandtitleforclient,
        v2.decisionmakerandtitleforclient,
        v2.opportunityname,
        v2.opptype,
        v2.opptypegroup,
        v2.saletype,
        v2.customerresponsedeadline,
        v2.desiredgolivedate,
        v2.targetcontractlength,
        v2.autorenewalclause,
        v2.autorenewalclausecomments,
        v2.termforconveinence,
        v2.termforconveinencecomments,
        v2.currentcontractacv,
        v2.quotenumber,
        v2.productname,
        v2.productcode,
        v2.cleanproductcode,
        v2.paldealapproval,
        v2.palproductapproval,
        v2.buproductapproval,
        v2.businessunit,
        v2.lineofbusiness,
        v2.cleanlineofbusiness,
        v2.pricingtype,
        v2.tierstairstep,
        v2.priceadjustmentbyproduct,
        v2.nonstandardpricing,
        v2.proposedpricelessthancurrentprice,
        v2.sojmixchange,
        v2.sojs,
        v2.package,
        v2.imepeerspecificvendorpanelorexclusive,
        v2.imepeerspecificsizeofvendorpanel,
        v2.imepeerspecificsharepercentage,
        v2.unitofmeasure,
        v2.volumechange,
        v2.expectedvolume,
        v2.floorprice,
        v2.targetprice,
        v2.acvatproposedfloor,
        v2.comments,
        v2.brandinvoiceoffawp,
        v2.genericinvoiceoffawp,
        v2.brandinvoicedispensefee,
        v2.genericinvoicedispensefee,
        v2.rebatesharedwithcustomer,
        v2.perscriptfeetocustomer,
        v2.networkpenetration,
        v2.brandratio,
        v2.genericratio,
        v2.brandawp,
        v2.genericawp,
        v2.approver,
        v2.suggestedfloor,
        v2.suggestedtarget,
        v2.suggestedbrandinvoiceoffawp,
        v2.suggestedgenericinvoiceoffawp,
        v2.suggestedbrandinvoicedispensefee,
        v2.suggestedgenericinvoicedispensefee,
        v2.suggestedrebatesharedwithcustomer,
        v2.suggestedperscriptfeetocustomer,
        v2.suggestednetworkpenetration,
        v2.suggestedbrandratio,
        v2.suggestedgenericratio,
        v2.suggestedbrandawp,
        v2.suggestedgenericawp,
        v2.productlinecommentsforsalesteammember,
        v2.comprehensivepricingcommentsforcmoandspteam,
        v2.comprehensivepricingcommentsforsalesteammember,
        v2.rush,
        v2.seltnomination,
        v2.preapprovedforall,
        v2.resubmission,
        v2.spowner,
        v2.approvaltypeid,
        v2.trueapprovalrouting,
        v2.standardtat,
        v2.circumventprocess,
        v2.spcommentary,
        v2.liaisonengaged,
        v2.volumechangetocurrent,
        v2.pricingchangetocurrent,
        v2.revenuechangetocurrent,
        v2.cpichangetocurrent,
        v2.sfproductid,
        v2.oppid,
        v2.lineitemid,
        v2.quotelineid,
        v2.priceoutlierstatus,
        v2.volumecategory,
        v2.q1floorprice,
        v2.q3floorprice,
        v2.iqrfloorprice,
        v2.lowerboundfloorprice,
        v2.upperboundfloorprice,
        v2.totaloccurrences,
        v2.minfloorprice,
        v2.maxfloorprice,
        v2.avgfloorprice,
        v2.nopackageflooracv,
        v2.totalnonpackageacv,
        v2.totalacvchangetocurrent,
        v2.dealopptypegroup,
        v2.mettat,
        v2.tatrequestedclean,
        v2.renewalleadtimeclean,
        v2.increaseatleastonce,
        cast(v2.date_yr1 as date) as date_yr1,
        cast(v2.date_yr2 as date) as date_yr2,
        cast(v2.date_yr3 as date) as date_yr3,
        cast(v2.date_yr4 as date) as date_yr4,
        cast(v2.date_yr5 as date) as date_yr5,

        sf.opportunity_type,
        sf.stage,
        coalesce(sf.close_date, cast(v2.date_yr1 as date)) as close_date,

        pl.rgo_sub_sub_product,
        pl.listprice

    from dealdashboardv2 v2

    left join salesforce_data sf
        on v2.oppid = sf.opportunity_id_case_safe

    left join pricingprodlist pl
        on lower(replace(v2.cleanproductcode, ' ', ''))
           = lower(replace(pl.productcode, ' ', ''))

    where v2.active = true

),

cleaned_metrics as (

    select
        *,

        case
            when lower(stage) in ('won: contract signed', 'closed won') then 'Won'
            when lower(stage) = 'closed lost' then 'Lost'
            else 'Pending'
        end as deal_status,

        case
            when dealcomplete is not null then
                right(cast(year(dealcomplete) as varchar), 2)
                || ' Q' || cast(ceil(month(dealcomplete) / 3.0) as varchar)
            else null
        end as quarter_year,

        cast(
            case
                when dealcomplete is null then null
                when close_date is null then null
                else datediff(day, dealcomplete, close_date)
            end as int
        ) as days_to_close,

        listprice as priceprodlistmatch,

        case
            when targetcontractlength is null then 3
            when targetcontractlength = 0 then 1
            else round(targetcontractlength, 0)
        end as adj_targetcontractlength

    from raw_joins

),

revenue_projections as (

    select
        *,

        nopackageflooracv as calc_rev_yr1,

        case
            when adj_targetcontractlength >= 2 and cpichangetocurrent is not null
                then (1 + cpichangetocurrent) * nopackageflooracv
            when adj_targetcontractlength >= 2
                then nopackageflooracv
            else 0
        end as calc_rev_yr2,

        case
            when adj_targetcontractlength >= 3
             and cpichangetocurrent is not null
                then nopackageflooracv * power(1 + cpichangetocurrent, 2)
            when adj_targetcontractlength >= 3
                then nopackageflooracv
            else 0
        end as calc_rev_yr3,

        -- Year 4
        case
            when adj_targetcontractlength >= 4
             and cpichangetocurrent is not null
                then nopackageflooracv * power(1 + cpichangetocurrent, 3)
            when adj_targetcontractlength >= 4
                then nopackageflooracv
            else 0
        end as calc_rev_yr4,

        -- Year 5
        case
            when adj_targetcontractlength >= 5
             and cpichangetocurrent is not null
                then nopackageflooracv * power(1 + cpichangetocurrent, 4)
            when adj_targetcontractlength >= 5
                then nopackageflooracv
            else 0
        end as calc_rev_yr5


    from cleaned_metrics

),

final_calculations as (

    select
        *,

        case
            when expectedvolume is null
              or pricingchangetocurrent is null
              or package = 'Yes'
                then 0
            else expectedvolume * pricingchangetocurrent
        end as revchange_yr1,

        case
            when calc_rev_yr2 is null or calc_rev_yr2 = 0
              or nopackageflooracv is null or nopackageflooracv = 0
                then 0
            else calc_rev_yr2 - nopackageflooracv
        end as revchange_yr2,

        case
            when calc_rev_yr3 is null or calc_rev_yr3 = 0
              or nopackageflooracv is null or nopackageflooracv = 0
                then 0
            else calc_rev_yr3 - calc_rev_yr2
        end as revchange_yr3,

        case
            when calc_rev_yr4 is null or calc_rev_yr4 = 0
              or nopackageflooracv is null or nopackageflooracv = 0
                then 0
            else calc_rev_yr4 - calc_rev_yr3
        end as revchange_yr4,

        case
            when calc_rev_yr5 is null or calc_rev_yr5 = 0
              or nopackageflooracv is null or nopackageflooracv = 0
                then 0
            else calc_rev_yr5 - calc_rev_yr4
        end as revchange_yr5

    from revenue_projections

)
select
    productid,
    dealid,
    originaldealid,
    active,
    mainopportunity,
    accountname,
    dealdescription,
    rundate,
    intakesheetreceived,
    intakesheetfinalized,
    spvalidationcomplete,
    intakesheetconsumedandpalapplied,
    buproductreversestagingpopulated,
    spmanualreviewofpaloutput,
    tatcommunicatedtoliaison,
    buoutputgenerated,
    buoutputemailed,
    spreceivesandvalidatesbuoutput,
    allproductpricingdeterminationscomplete,
    communicationtoliaisonwithfinalpricing,
    sschallengebualternatepricing,
    challengemeeting,
    buoutputformupdatedwithchallengeoutcome,
    dealcomplete,
    tatactual,
    tatrequested,
    renewalleadtime,
    dealstage,
    salesexecutive,
    clientservicesexecutive,
    submittor,
    resubmissionreason,
    accounttype,
    accountmotivation,
    accounthealth,
    accounthealthexplanation,
    accountsegment,
    accountbudget,
    accountbudgetyear,
    clientbuyingmotivation,
    pointofcontactandtitleforclient,
    decisionmakerandtitleforclient,
    opportunityname,
    opptype,
    opptypegroup,
    saletype,
    customerresponsedeadline,
    desiredgolivedate,
    targetcontractlength,
    autorenewalclause,
    autorenewalclausecomments,
    termforconveinence,
    termforconveinencecomments,
    currentcontractacv,
    quotenumber,
    productname,
    productcode,
    cleanproductcode,
    paldealapproval,
    palproductapproval,
    buproductapproval,
    businessunit,
    lineofbusiness,
    cleanlineofbusiness,
    pricingtype,
    tierstairstep,
    priceadjustmentbyproduct,
    nonstandardpricing,
    proposedpricelessthancurrentprice,
    sojmixchange,
    sojs,
    package,
    imepeerspecificvendorpanelorexclusive,
    imepeerspecificsizeofvendorpanel,
    imepeerspecificsharepercentage,
    unitofmeasure,
    volumechange,
    expectedvolume,
    floorprice,
    targetprice,
    acvatproposedfloor,
    comments,
    brandinvoiceoffawp,
    genericinvoiceoffawp,
    brandinvoicedispensefee,
    genericinvoicedispensefee,
    rebatesharedwithcustomer,
    perscriptfeetocustomer,
    networkpenetration,
    brandratio,
    genericratio,
    brandawp,
    genericawp,
    approver,
    suggestedfloor,
    suggestedtarget,
    suggestedbrandinvoiceoffawp,
    suggestedgenericinvoiceoffawp,
    suggestedbrandinvoicedispensefee,
    suggestedgenericinvoicedispensefee,
    suggestedrebatesharedwithcustomer,
    suggestedperscriptfeetocustomer,
    suggestednetworkpenetration,
    suggestedbrandratio,
    suggestedgenericratio,
    suggestedbrandawp,
    suggestedgenericawp,
    productlinecommentsforsalesteammember,
    comprehensivepricingcommentsforcmoandspteam,
    comprehensivepricingcommentsforsalesteammember,
    rush,
    seltnomination,
    preapprovedforall,
    resubmission,
    spowner,
    approvaltypeid,
    trueapprovalrouting,
    standardtat,
    circumventprocess,
    spcommentary,
    liaisonengaged,
    volumechangetocurrent,
    pricingchangetocurrent,
    revenuechangetocurrent,
    cpichangetocurrent,
    sfproductid,
    oppid,
    lineitemid,
    quotelineid,
    priceoutlierstatus,
    volumecategory,
    q1floorprice,
    q3floorprice,
    iqrfloorprice,
    lowerboundfloorprice,
    upperboundfloorprice,
    totaloccurrences,
    minfloorprice,
    maxfloorprice,
    avgfloorprice,
    nopackageflooracv,
    totalnonpackageacv,
    totalacvchangetocurrent,
    dealopptypegroup,
    mettat,
    tatrequestedclean,
    renewalleadtimeclean,
    increaseatleastonce,
    date_yr1,
    date_yr2,
    date_yr3,
    date_yr4,
    date_yr5,
    opportunity_type,
    stage,
    close_date,
    rgo_sub_sub_product,
    listprice,
    deal_status,
    quarter_year,
    days_to_close,
    priceprodlistmatch,
    adj_targetcontractlength,
    calc_rev_yr1,
    calc_rev_yr2,
    calc_rev_yr3,
    calc_rev_yr4,
    calc_rev_yr5,
    revchange_yr1,
    revchange_yr2,
    revchange_yr3,
    revchange_yr4,
    revchange_yr5
 from final_calculations
