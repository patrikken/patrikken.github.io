library(stringr)
library(dplyr)
library(googlesheets4)
library(lubridate)
library(glue)
library(purrr)

gs4_deauth()

# function to get sheet from google doc spreadsheets
get_cv_sheet <- function(sheet) {
    return(read_sheet(
        ss = 'https://docs.google.com/spreadsheets/d/12-OFmeWUKrpV1Iw-7MgFVvA5rVCjfL7fXu1diVyz6aA/edit?usp=sharing',
        sheet = sheet
    ))
}

# function to get all sheets from google doc spreadsheets. better to reduce api calls.
get_cv_data <- function(ss_url = 'https://docs.google.com/spreadsheets/d/12-OFmeWUKrpV1Iw-7MgFVvA5rVCjfL7fXu1diVyz6aA/edit?usp=sharing') {
  # Get all sheet names
  sheet_names <- sheet_names(ss_url)
  
  # Read all sheets into a named list
  all_sheets <- sheet_names %>%
    set_names() %>%
    map(~read_sheet(ss = ss_url, sheet = .))
  
  # Return a function to access individual sheets
  function(sheet = NULL) {
    if (is.null(sheet)) {
      return(all_sheets)  # Return all sheets if no specific sheet is requested
    } else if (sheet %in% names(all_sheets)) {
      return(all_sheets[[sheet]])  # Return the requested sheet
    } else {
      stop(paste("Sheet", sheet, "not found in the spreadsheet"))
    }
  }
}

# function to format budget and add dollar sign
format_budget <- function(amount) {
    amount <- as.numeric(amount)
    formatted_amount <- format(amount, big.mark = ",", scientific = FALSE)
    return(paste0("$", trimws(formatted_amount)))
}



