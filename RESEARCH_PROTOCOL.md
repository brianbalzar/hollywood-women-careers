# Research protocol: age and acting opportunity

Status: feasibility protocol, version 0.1

## Primary question

Among performers who recently held an IMDb principal acting credit, how does the
annual probability of another principal acting credit change with age, and how
does that age curve differ between people predominantly credited in IMDb's
`actress` and `actor` categories?

The analysis calls these *women-coded* and *men-coded credit classes*. IMDb's
categories are production metadata and are not treated as definitive measures
of gender identity.

## Key descriptive definitions

- **Women-coded opportunity share:** principal opportunities credited to
  women-coded performers divided by those credited to women-coded plus
  men-coded performers at the same age and scope.
- **Five-year career interruption:** the last credited year before at least
  five consecutive calendar years without another qualifying principal credit.
  This is a confirmed interruption, not necessarily permanent retirement.
- **Career taper ratio:** opportunities in a trailing five-year window divided
  by the performer's highest observed five-year total, evaluated after the first
  peak window among performers whose observed peak contains at least four
  opportunities. Severe tapering is a ratio at or below 25% in a year when the
  performer still receives a qualifying credit.

## Primary estimand

For age `a` and credit class `g`:

`P(at least one principal acting credit in year t | a, g, principal credit in one of the prior five years)`

The primary contrast is a normalized retention index:

`women-coded retention relative to ages 30-34 / men-coded retention relative to ages 30-34`

This ratio-of-ratios asks whether opportunity contracts faster for one group,
while avoiding a misleading comparison of raw credit totals alone.

## Initial scope

- Release years: 2000 through the latest substantially complete calendar year;
  source extraction begins in 1995 to establish prior activity
- Performer ages: 18 through 80
- Media analyzed separately:
  - feature films
  - television episodes, later aggregated to series-year participation
- Market scope: titles with a U.S.-region IMDb alternative title; television
  episodes may inherit U.S.-market status and genre from the parent series
- Excluded genres: documentary, news, reality television, talk show, game show,
  and adult
- Substantial credit definition: IMDb principal cast credit
- Prominence sensitivity: first three, first five, and all principal cast credits
- Recent-activity windows: three, five (primary), and seven years

## Performer classification

For each performer, count IMDb principal credits categorized as `actress` and
`actor`. Assign a predominant class only when at least 90% of classified credits
fall in one category. Retain all other performers as ambiguous and report their
number. Repeat key results at 80%, 95%, and credit-level classification.

## Planned outputs

1. Age-specific opportunity curves with uncertainty intervals
2. Normalized retention curves and women-to-men retention ratios
3. Estimated change points, with bootstrap uncertainty
4. Career-continuity survival curves, treating end-of-data careers as censored
5. Prominence, medium, genre, cohort, and prior-success sensitivity analyses
6. Post-peak career-taper curves among performers who continue receiving credits

## Bias and uncertainty checks

- Birth and release years are year-level, making calculated age uncertain by
  approximately one year.
- IMDb principal credits are a prominence proxy, not a complete employment list.
- U.S.-region alternative titles indicate U.S. exhibition, not necessarily U.S.
  production ownership or filming location.
- A missing credit does not establish involuntary unemployment.
- Reduced credit volume does not reveal whether tapering was voluntary or caused
  by fewer available opportunities.
- Television episode credits cannot be compared directly with feature-film
  credits; primary results keep media separate.
- Historical period, birth cohort, race/ethnicity, and prior career success may
  confound simple age comparisons and will be modeled explicitly where data
  permit.
- Death years will be used for censoring, not counted as career attrition.
- The latest release year may be incomplete and will be excluded until coverage
  diagnostics show otherwise.

## Character-content phase

The later character study will sample titles within age, credit class, medium,
year, and prominence strata. It will code occupational identity, authority,
independent objectives, romantic agency, parent/grandparent status, widowhood,
and whether aging or appearance drives the story. A human-reviewed validation
sample and inter-rater agreement are required before scaling automated coding.

## Billboard Hot 100 extension

The parallel music analysis covers 1995–2025 and uses one identifiable solo
artist per chart year as its primary opportunity unit. A unique artist-week
sensitivity gives sustained chart visibility additional weight. Artist names
must resolve conservatively to a human entity with birth-year, gender, and
MusicBrainz metadata; groups, unresolved collaborations, and ambiguous matches
are excluded rather than assigned a gender.

Primary music outputs are age-distribution box plots, shares aged 35+, 40+, and
50+, women’s share of classified solo participation by age, and the probability
of another chart-active year within five years. Chart methodology changes over
time, and chart presence measures commercial visibility rather than recording
employment, artistic output, touring, or causal discrimination.

## Claims this study cannot make alone

The public-credit analysis cannot identify audition pools, offers, availability,
voluntary retirement, caregiving constraints, or rejected roles. It can quantify
an observed opportunity gap and test when it appears; causal attribution requires
casting, audition, union-employment, or earnings data.
