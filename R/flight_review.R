suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(scales)
})

required_columns <- c(
  "YEAR", "DAY_OF_WEEK", "FL_DATE",
  "ORIGIN_AIRPORT_ID", "ORIGIN_CITY_NAME",
  "DEST_AIRPORT_ID", "DEST_CITY_NAME",
  "DEP_DELAY", "ARR_TIME", "ARR_DELAY", "ARR_DELAY_NEW", "ARR_DEL15"
)

wilson_interval <- function(successes, trials, level = 0.95) {
  if (trials <= 0) {
    return(list(lower = NA_real_, upper = NA_real_))
  }
  z <- qnorm(1 - (1 - level) / 2)
  p <- successes / trials
  denominator <- 1 + z^2 / trials
  centre <- (p + z^2 / (2 * trials)) / denominator
  half_width <- z * sqrt((p * (1 - p) + z^2 / (4 * trials)) / trials) /
    denominator
  list(
    lower = pmax(0, centre - half_width),
    upper = pmin(1, centre + half_width)
  )
}

valid_hhmm <- function(x) {
  known <- !is.na(x)
  value <- suppressWarnings(as.integer(x))
  hour <- value %/% 100L
  minute <- value %% 100L
  valid <- !known |
    (value >= 0L & value <= 2400L & minute < 60L &
       (hour < 24L | (hour == 24L & minute == 0L)))
  valid
}

load_and_audit_flights <- function(data_path) {
  flights <- fread(
    data_path,
    na.strings = c("", "NA"),
    strip.white = TRUE,
    showProgress = FALSE
  )
  setnames(flights, toupper(trimws(names(flights))))

  empty_columns <- names(flights)[
    vapply(flights, function(x) all(is.na(x) | trimws(as.character(x)) == ""), logical(1))
  ]
  if (length(empty_columns) > 0L) {
    flights[, (empty_columns) := NULL]
  }

  missing_columns <- setdiff(required_columns, names(flights))
  if (length(missing_columns) > 0L) {
    stop("Missing required columns: ", paste(missing_columns, collapse = ", "))
  }

  numeric_columns <- c(
    "YEAR", "DAY_OF_WEEK", "ORIGIN_AIRPORT_ID", "DEST_AIRPORT_ID",
    "DEP_DELAY", "ARR_TIME", "ARR_DELAY", "ARR_DELAY_NEW", "ARR_DEL15"
  )
  flights[, (numeric_columns) := lapply(.SD, as.numeric), .SDcols = numeric_columns]
  flights[, FL_DATE := as.IDate(FL_DATE)]

  expected_day <- ((as.POSIXlt(as.Date(flights$FL_DATE))$wday + 6L) %% 7L) + 1L
  day_mismatch <- !is.na(flights$DAY_OF_WEEK) & flights$DAY_OF_WEEK != expected_day

  known_arrival <- !is.na(flights$ARR_DELAY)
  known_delay_new <- !is.na(flights$ARR_DELAY_NEW)
  known_late_flag <- !is.na(flights$ARR_DEL15)
  delay_new_mismatch <- known_arrival & known_delay_new &
    abs(flights$ARR_DELAY_NEW - pmax(flights$ARR_DELAY, 0)) > 1e-8
  late_flag_mismatch <- known_arrival & known_late_flag &
    flights$ARR_DEL15 != as.numeric(flights$ARR_DELAY >= 15)

  source_columns <- names(flights)
  duplicate_rows <- duplicated(flights[, ..source_columns])

  audit <- data.table(
    check = c(
      "Source records",
      "Usable source fields",
      "All records from January 2019",
      "Day-of-week mismatches",
      "Invalid known arrival-time HHMM values",
      "Arrival-delay-new contradictions",
      "Late-15 flag contradictions",
      "Indistinguishable duplicate rows",
      "Missing departure delay",
      "Missing arrival delay"
    ),
    value = c(
      nrow(flights),
      ncol(flights),
      sum(!is.na(flights$FL_DATE) &
            format(as.Date(flights$FL_DATE), "%Y-%m") == "2019-01"),
      sum(day_mismatch, na.rm = TRUE),
      sum(!valid_hhmm(flights$ARR_TIME), na.rm = TRUE),
      sum(delay_new_mismatch, na.rm = TRUE),
      sum(late_flag_mismatch, na.rm = TRUE),
      sum(duplicate_rows),
      sum(is.na(flights$DEP_DELAY)),
      sum(is.na(flights$ARR_DELAY))
    )
  )

  if (any(is.na(flights$FL_DATE))) {
    stop("At least one flight date could not be parsed.")
  }
  if (!all(format(as.Date(flights$FL_DATE), "%Y-%m") == "2019-01")) {
    stop("The supplied file is not limited to January 2019.")
  }

  list(flights = flights, audit = audit)
}

daily_summary <- function(flights) {
  daily <- flights[, {
    known_arr <- !is.na(ARR_DELAY)
    known_dep_arr <- !is.na(ARR_DELAY) & !is.na(DEP_DELAY)
    late15 <- sum(ARR_DELAY >= 15, na.rm = TRUE)
    n_known <- sum(known_arr)
    interval <- wilson_interval(late15, n_known)
    values <- ARR_DELAY[known_arr]

    list(
      flights = .N,
      known_arrivals = n_known,
      arrival_missing_rate = mean(!known_arr),
      mean_arrival_delay = mean(values),
      mean_arrival_delay_se = sd(values) / sqrt(n_known),
      median_arrival_delay = median(values),
      p95_arrival_delay = as.numeric(quantile(values, 0.95, names = FALSE)),
      late15_rate = late15 / n_known,
      late15_lower = interval$lower,
      late15_upper = interval$upper,
      severe60_rate = mean(ARR_DELAY >= 60, na.rm = TRUE),
      worsening60_rate = if (any(known_dep_arr)) {
        mean((ARR_DELAY - DEP_DELAY)[known_dep_arr] >= 60)
      } else {
        NA_real_
      }
    )
  }, by = FL_DATE]

  severity_metrics <- c(
    "mean_arrival_delay", "p95_arrival_delay", "late15_rate",
    "severe60_rate", "worsening60_rate"
  )
  for (metric in severity_metrics) {
    daily[, paste0(metric, "_rank") := frank(get(metric), ties.method = "average") / .N]
  }
  rank_columns <- paste0(severity_metrics, "_rank")
  daily[, priority_score := 100 * rowMeans(.SD), .SDcols = rank_columns]
  setorder(daily, -priority_score, FL_DATE)
  daily[, priority_rank := seq_len(.N)]
  setorder(daily, FL_DATE)
  daily
}

score_sensitivity <- function(daily) {
  metrics <- c(
    "mean_arrival_delay", "p95_arrival_delay", "late15_rate",
    "severe60_rate", "worsening60_rate"
  )
  full_top <- daily[order(-priority_score)][1:5, FL_DATE]
  rbindlist(lapply(metrics, function(excluded) {
    retained <- setdiff(metrics, excluded)
    ranks <- paste0(retained, "_rank")
    score <- rowMeans(daily[, ..ranks])
    top <- daily[order(-score)][1:5, FL_DATE]
    data.table(
      excluded_metric = excluded,
      overlap_with_full_top5 = length(intersect(full_top, top)),
      top5_dates = paste(as.character(sort(top)), collapse = ", ")
    )
  }))
}

make_figures <- function(daily, audit, output_dir) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  priority_dates <- daily[priority_rank <= 5, FL_DATE]

  p_late <- ggplot(daily, aes(x = as.Date(FL_DATE), y = late15_rate)) +
    geom_ribbon(aes(ymin = late15_lower, ymax = late15_upper),
                fill = "#9ecae1", alpha = 0.35) +
    geom_line(color = "#08519c", linewidth = 0.8) +
    geom_point(
      data = daily[FL_DATE %in% priority_dates],
      color = "#b2182b", size = 2.2
    ) +
    scale_y_continuous(labels = percent_format(accuracy = 1)) +
    scale_x_date(date_breaks = "3 days", date_labels = "%b %d") +
    labs(
      title = "Daily share of flights arriving at least 15 minutes late",
      subtitle = "Ribbon shows a 95% Wilson interval; red points are the five highest composite-review dates",
      x = NULL, y = "Late-arrival share"
    ) +
    theme_minimal(base_size = 11) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))

  p_delay <- ggplot(daily, aes(x = as.Date(FL_DATE))) +
    geom_line(aes(y = mean_arrival_delay, color = "Mean"), linewidth = 0.8) +
    geom_line(aes(y = p95_arrival_delay, color = "95th percentile"), linewidth = 0.8) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey45") +
    scale_color_manual(values = c("Mean" = "#2166ac", "95th percentile" = "#b2182b")) +
    scale_x_date(date_breaks = "3 days", date_labels = "%b %d") +
    labs(
      title = "Daily arrival-delay severity",
      x = NULL, y = "Minutes", color = "Measure"
    ) +
    theme_minimal(base_size = 11) +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1),
      legend.position = "bottom"
    )

  missingness <- audit[check %chin% c("Missing departure delay", "Missing arrival delay")]
  missingness[, rate := value / audit[check == "Source records", value]]
  p_missing <- ggplot(missingness, aes(x = reorder(check, rate), y = rate)) +
    geom_col(fill = "#636363", width = 0.62) +
    coord_flip() +
    scale_y_continuous(labels = percent_format(accuracy = 0.1)) +
    labs(title = "Missing delay outcomes", x = NULL, y = "Share of source records") +
    theme_minimal(base_size = 11)

  ggsave(file.path(output_dir, "daily_late15_rate.png"), p_late,
         width = 9, height = 5.2, dpi = 180)
  ggsave(file.path(output_dir, "daily_delay_severity.png"), p_delay,
         width = 9, height = 5.2, dpi = 180)
  ggsave(file.path(output_dir, "missingness.png"), p_missing,
         width = 7.5, height = 3.8, dpi = 180)
}

run_flight_review <- function(data_path, output_dir) {
  if (!file.exists(data_path)) {
    stop("Flight data file not found: ", data_path)
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  loaded <- load_and_audit_flights(data_path)
  daily <- daily_summary(loaded$flights)
  sensitivity <- score_sensitivity(daily)
  top_dates <- daily[order(priority_rank)][1:10]

  fwrite(loaded$audit, file.path(output_dir, "data_audit.csv"))
  fwrite(daily, file.path(output_dir, "daily_summary.csv"))
  fwrite(top_dates, file.path(output_dir, "priority_dates.csv"))
  fwrite(sensitivity, file.path(output_dir, "score_sensitivity.csv"))
  make_figures(daily, loaded$audit, output_dir)

  invisible(list(
    audit = loaded$audit,
    daily = daily,
    priority_dates = top_dates,
    sensitivity = sensitivity
  ))
}
