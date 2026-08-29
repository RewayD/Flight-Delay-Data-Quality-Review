# Changes from the course submission

This is a focused portfolio rewrite, not a replacement for the archived team
submission.

- Removed all student numbers and unrelated team sections.
- Narrowed the question to data quality and priority dates, matching the work
  this repository is intended to demonstrate.
- Removed the 2,000-line monolithic report structure.
- Split reusable analysis logic from the rendered report.
- Replaced Downloads-folder fallbacks and numbered filenames with an explicit
  command-line data path.
- Added required-column and date-range validation.
- Added day-of-week, HHMM, derived-delay-field, late-flag, duplicate, and
  missing-outcome checks.
- Retained missing outcomes instead of treating them as successful flights.
- Added Wilson uncertainty intervals for daily late-arrival rates.
- Replaced anomaly-confidence language with a transparent relative review
  score.
- Added a leave-one-metric-out score sensitivity analysis.
- Limited conclusions to investigation priorities; no causal explanations are
  inferred from fields that are not present.
- Excluded the large raw CSV and documented the official BTS retrieval route.
- Added a fixed report date and a one-command reproducible render.
- Added transparent attribution, permission, and AI-assistance notes for the
  post-course portfolio rewrite.
