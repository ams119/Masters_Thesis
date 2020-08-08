#!/bin/env Rscript
# Author: Anne Marie Saunders
# Script: gam_batch.R
# Desc: This script uses the functions from gam_functions.R and runs them iteratively on all location and temporal aggregation files. It then compiles all locations into 3 datasets of weekly, biweekly, and monthly data
# Arguments: 
# Date: 07/28/20

# Load functions from gam_functions.R
source("gam_functions.R")
library(tidyverse)

# List all aggregated files 
path = "../Data/Extracted_Data/Aggregated/"
files = list.files(path)

# Only include focal locations
locations = sort(c("Manatee", "Lee", "Walton", "Saint_Johns", "Orange"))
files = files[grep(pattern = paste(locations, collapse = "|"), x = files)]

# Organize through alphebetisation into matrix by location for rows and by temporal scale for columns
files = matrix(sort(files), nrow = length(unique(locations)), byrow = T)

# Loop through each temporal scale
for(i in 1:ncol(files)){
  
  # Create empty list to store all location output tables at the temporal scale
  output_list = vector("list", length = nrow(files))
  
  # Define the time scale for these datasets
  scale = c("biweekly", "monthly", "weekly")[i]
  
  # Loop through each location in this temporal scale
  for(j in 1:nrow(files)){
    
    # Read in dataset
    data = read.csv(paste0(path, files[j,i]), header = T, stringsAsFactors = F)
    
    # Extract a vector of all species at this location. Column numbers change based on temporal scale.
    # if(scale == 'weekly'){
    #   species = colnames(data[10:(dim(data)[2]-4)])
    # }
    # 
    # if(scale == 'biweekly' | scale == 'monthly'){
    #   species = colnames(data[10:(dim(data)[2]-3)])
    # }
    
    species = colnames(data[10:(dim(data)[2]-3)])
    
    # Create vectors identifying the lags at this temporal scale
    lags = make_laglists(scale = scale)
    
    # Create a data frame of lagged meteorological values
    lag_table = make_lag_table(temp = data$temp_mean, precip = data$precip_days, lags = lags)
    
    # Create empty output matrix
    output = make_output(lags = lags, species = species)
    
    # Add a column describing the location
    output$Location = locations[j]
    
    # Fit univariate models and store in this output table
    output = fit_univariate_GAMs(data = data, output = output, lags = lags, lag_table = lag_table, species = species, scale = scale)
    
    # Fit multivariate models and store in this output table
    output = fit_multivariate_GAMs(data = data, output = output, lags = lags, lag_table = lag_table, species = species, scale = scale)
    
    # Append this output table to the total output list for this time scale
    output_list[[j]] = output
  }
  
  # Join each list together into one dataframe for this temporal scale
  output_df  = bind_rows(output_list)
  
  # Save as csv
  write.csv(output_df, file = paste0("../Results/GAM2_", scale, ".csv"), row.names = F)
  
  
}

