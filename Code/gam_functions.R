#!/bin/env Rscript
# Author: Anne Marie Saunders
# Script: gam_functions.R
# Desc: This script contains the functions necessary for model fitting and selection 
# Arguments: 
# Date: 07/25/20

#### Libraries ####
library(mgcv)

#### Functions ####

# This function pre-processes precipitation, temperature, and abundance values for fitting with GAM
# by creating autoregressive x variable and removing rows with NA values in any of the x or y variables.
# It also prepares abundance variables for logging by adding 1. It returns adjusted temperature, 
# precipitation, and abundance vectors as well as a new autoregressive abundance vector
prep_variables = function(temp, precip, abundance, years, caldates){
  
  
  # Find NA indexes in all variables 
  find_nas = which(is.na(abundance) | is.na(temp) | is.na(precip))
  
  # remove these indexes from all variables
  indexes = seq(1, length(abundance), 1)[-find_nas]
  abundance = abundance[-find_nas]
  temp = temp[-find_nas]
  precip = precip[-find_nas]
  years = years[-find_nas]
  caldates = caldates[-find_nas]
  
  
  #return(data.frame(abundance, temp, precip, AR1, years))
  return(data.frame(abundance, temp, precip, caldates, years, indexes))
  
}

# This function makes appropriate column names with length according to the temporal scale
make_laglists = function(scale){
  if(scale == 'weekly'){
    templags = paste0(rep('temp_lag', 13), 0:12)
    preciplags = paste0(rep('precip_lag', 13), 0:12)
  }
  
  if(scale == 'biweekly'){
    templags = paste0(rep('temp_lag', 6), 0:5)
    preciplags = paste0(rep('precip_lag', 6), 0:5)
  }
  
  if(scale == 'monthly'){
    templags = paste0(rep('temp_lag', 3), 0:2)
    preciplags = paste0(rep('precip_lag', 3), 0:2)
  }
  
  return(list(temp = templags, precip = preciplags))
}

# Make an empty output data frame for each location
make_output = function(lags, species){
  
  # Create desired column names
  columns = c("Species", lags$temp, lags$precip, "nr_total_obs", "nr_bestfit_obs", "nr_nonzero_obs", "p", 
              "z_inflation_pct", "Best_Temp", "AIC_wt_temp", "Best_Precip", "AIC_wt_precip", "Multi_DevianceExplained", "Multi_AIC", "Ljung_Box",
              "Multi_MAE", "Multi_NMAE", "Multi_MB", "Multi_Blocks","Multi_SignifVariables", "MultiAR_DevianceExplained", 
              "MultiAR_AIC", "MultiAR_MAE", "MultiAR_NMAE", "MultiAR_MB", "MultiAR_Blocks","MultiAR_SignifVariables")
  
  # Create an empty dataframe with of appropriate size
  output = data.frame(matrix(NA, nrow = length(species), ncol = length(columns)))
  
  # Give descriptive column names
  colnames(output) = columns
  
  # Name each row with species names 
  output$Species = species
  
  # Return completed output table
  return(output)
  
}

# Make a data table of lagged temperature and precipitation values
make_lag_table = function(temp, precip, lags){
  
  # Create empty data frame to be filled by lagged values
  lag_table = data.frame(matrix(NA, nrow = length(temp), ncol = length(lags$temp)*2))
  
  # Set column names to the type of lag
  colnames(lag_table) = c(lags$temp, lags$precip)
  
  # In each of the temperature columns add sequentially NAs at start and remove values from end to create lags
  for(i in 1:length(lags$temp)){
    lag = i-1
    lag_table[,i] = c(rep(NA, lag), temp[1:(length(temp)-lag)])
  }
  
  # Do the same in each of the precipitation columns- these begin in the length(lags$temp)+1 column
  for(i in 1:length(lags$precip)){
    lag = i-1
    lag_table[,length(lags$temp) + i] = c(rep(NA, lag), precip[1:(length(precip)-lag)])
  }
  
  # Return completed lag table
  return(lag_table)
}

fit_univariate_GAMs = function(ts_data, output, lags, lag_table, species, scale){
  
  ## Fit univariate models with each species abundance vector ##
  for(i in 1:length(species)){
    
    cat(paste0("\n*********************************************************\n\nNow evaluating univariate GAMs for species ", 
               i, ', \n', species[i], " at ", scale, " ", output$Location[i], '\n'))
    
    output$nr_total_obs[i] = sum(!is.na(ts_data[[species[i]]]), years = ts_data$Year)
    
    # Create a loose guess at z_inflation_pct for this dataset
    output$z_inflation_pct[i] = round(sum(ts_data[[species[i]]] == 0, na.rm = T)/output$nr_total_obs[i]*100)
    
    # Highly zero inflated data takes forever to converge and we will cut it out anyway: just skip analysis to save time
    if(output$z_inflation_pct[i] >= 95){next}
    
    # Conduct univariate GAMs for each lags of each meteorological variable
    for(j in 1:length(lags$temp)){
      
      # Prepare all x and y variables
      vars = prep_variables(temp = lag_table[,j], precip = lag_table[,length(lags$temp) + j], 
                            abundance = ts_data[[species[i]]], years = ts_data$Year, caldates = ts_data$date)
      
      # Max number of knots (k) is = to the number of unique data points (discrete days of rainfall) 
      # Max number of basis functions is equal to k-1
      # Default k will be 10, but datasets with fewer unique values 10 than this will be adjusted accordingly
      precip_k = 10
      if(length(unique(vars$precip)) < 10){precip_k = length(unique(vars$precip))}
      
      # Fit temperature univariate model
      temp_gam = try(gam(abundance ~ s(temp, k = 10, bs = 'cr'), data = vars, family = tw, method = "REML"), silent = TRUE)
      if(class(temp_gam)[1] != "try-error"){
        output[[lags$temp[j]]][i] = AIC(temp_gam)
      }

      # Fit precipitation univariate model
      precip_gam = try(gam(abundance ~ s(precip, k = precip_k, bs = 'cr'), data = vars, family = tw, method = "REML"), silent = TRUE)
      
      if(class(precip_gam)[1] != "try-error"){
        output[[lags$precip[j]]][i] = AIC(precip_gam)
      }
      
      
    }
    
  }
  
  # Find row minimums for temperature and precipitation in output by finding the column name of the max.col
  # when output is multiplied by -1
  output$Best_Temp = colnames(output[,colnames(output) %in% lags$temp])[max.col(-output[,colnames(output) %in% lags$temp])]
  output$Best_Precip = colnames(output[,colnames(output) %in% lags$precip])[max.col(-output[,colnames(output) %in% lags$precip])]
  
  return(output)
}

fit_multivariate_GAMs = function(ts_data, output, lags, lag_table, species, scale){
  
  ## Fit multiivariate models with each species abundance vector ##
  for(i in 1:length(species)){
    
    cat(paste0("\n*********************************************************\n\nNow evaluating multivariate GAMs for species ", 
               i, ', \n', species[i], " at ", scale, " ", output$Location[i], '\n'))
    
    # Skip datasets where we didn't calculate best fit lags
    if(isTRUE(output$z_inflation_pct[i] >= 95)){next}
    
    # Prepare x and y variables. We'll use the best fit lags of temp and precip for each species 
    vars = prep_variables(temp = lag_table[[output$Best_Temp[i]]], precip = lag_table[[output$Best_Precip[i]]], 
                          abundance = ts_data[[species[i]]], years = ts_data$Year, caldates = ts_data$date)
    
    # Record the minimum number of observations in this dataset with this best fit lag
    output$nr_bestfit_obs[i] = length(vars$abundance)
    
    # Record the number of non-zero observations 
    output$nr_nonzero_obs[i] = length(which(vars$abundance != 0))
    
    # Re-calculate the zero inflation of this dataset with this best fit lag
    output$z_inflation_pct[i] = round(sum(vars$abundance == 0)/output$nr_bestfit_obs[i]*100)
    
    # Now skip the highly zero inflated datasets that aren't going to be used in analysis
    if(isTRUE(output$z_inflation_pct[i] >= 90)){next}
    
    # Calculate the akaike weights of the best fit temperature and precipitation lags
    output = akaike_weight(output_data = output, lags = lags, i = i)
    
    # Max number of basis splines is = to the number of unique data points (discrete days of rainfall) 
    # Thus max k (number of knots) is equal to nr of unique values + 1. 
    # Default will be 10, but datasets with fewer unique values 9 than this will be adjusted accordingly
    precip_k = 10
    if(length(unique(vars$precip)) < 10){precip_k = length(unique(vars$precip))}
    
    # Fit non-autoregressive multivariate model where smooth terms can be penalized out
    multi_gam = try(gam(abundance ~ s(temp, bs = 'cr', k = 10) + s(precip, k = precip_k, bs = 'cr'), 
                        data = vars, family = tw, method = "REML", select = TRUE), silent = TRUE)
    if(class(multi_gam)[1] != "try-error"){
      # Record the power index of this model
      output$p[i] = round(as.numeric(str_extract(pattern = "[0-9]\\.[0-9]*", summary(multi_gam)$family$family)), 1)
      # Record the AIC of this model
      output$Multi_AIC[i] = multi_gam$aic
      # Record deviance explained
      output$Multi_DevianceExplained[i] = round(100*summary(multi_gam)$dev.expl, 1)
      # Record which predictive terms are significant according p-value with alpha = 0.05
      output$Multi_SignifVariables[i] = paste0(c('temp', 'precip')[which(summary(multi_gam)$s.pv <= 0.05)], collapse = ",")
      # Record the Ljung-Box Significance value for the residuals: if p < 0.05, residuals are autocorrelated
      output$Ljung_Box = Box.test(multi_gam$residuals, type = "Ljung-Box")$p.value
      
      # Perform block cross validation to get CV scores (MAE and MAAPE)
      # Open plot for lines drawn during cross validation
      png(filename = paste0("../Results/Pred_Plots/", species[i], output$Location[i], scale, ".png"), height = 900, width = 900, units = 'px')
      plot(x = as.Date(vars$caldates, "%Y-%m-%d"), y = vars$abundance, type = "l", main = paste(scale, output$Location[i], species[i], output$Multi_SignifVariables[i]))
      cv_scores = block_cross_validate(vars = vars, precip_k = precip_k, type = "nonAR", plot = TRUE)
      dev.off()
      
      # Store results metrics of cross validation
      output$Multi_MAE[i] = cv_scores[1]
      output$Multi_NMAE[i] = cv_scores[2]
      output$Multi_MB[i] = cv_scores[3]
      output$Multi_Blocks[i] = cv_scores[4]
      
      # Plot the partial dependencies 
      png(filename = paste0("../Results/GAM_Plots/", scale, output$Location[i], species[i], ".png"), height = 900, width = 900, units = 'px')
      plot(multi_gam, rug = TRUE, page = 1, residuals = TRUE, main = paste(scale, output$Location[i], species[i]))
      dev.off()
      
      # Plot the fit plots: histograms of data distributions
      png(filename = paste0("../Results/Fit_Plots/", scale, output$Location[i], species[i], "dist.png"), height = 900, width = 900, units = 'px')
      hist(vars$abundance, col = "lightblue", main = paste("Histogram of log(abundance, z inflation =", output$z_inflation_pct[i]))
      dev.off()
      
      # and QQ and other diagnostic plots
      png(filename = paste0("../Results/Fit_Plots/", scale, output$Location[i], species[i], "modelcheck_tw.png"), height = 900, width = 900, units = 'px')
      plot_gam_check(multi_gam)
      dev.off()
        
    }
  }
  
  return(output)
}


# Create a function to perform k fold cross validation for AR and non AR models
block_cross_validate = function(vars, precip_k, type, plot){
  
  # Get vector of unique years
  yrs = unique(vars$years)
  
  # Count the number of blocks -> equal to the number of years
  nr_blocks = length(yrs)
  
  # Create vector to store MAE explained in each test
  MAE = rep(NA, nr_blocks)
  
  # Create vector to store NMAE explained in each test
  NMAE = rep(NA, nr_blocks)
  
  # Create vector to store MB explained in each test
  MB = rep(NA, nr_blocks)
  
  # Create a counter to record how many data points are considered in the weighted average of MAE
  pts_included = 0 
  
  ## Do block cross validation
  for(i in 1:nr_blocks){
    
    # Split vars into test and train by iteratively choosing 1 year
    test = vars %>% filter(years == yrs[i])
    train = vars %>% filter(years != yrs[i])
    
    if(type == "AR"){
      # Train AR gam model using training set
      gam = try(gam(abundance ~ s(temp, k = 10, bs = 'cr') + s(precip, k = precip_k, bs = 'cr') + s(log(AR1), k = 10, bs = 'cr'), 
              select = TRUE, data = train, family = tw,  method = "REML"), silent = TRUE)
    }
    
    if(type == "nonAR"){
      # Train a non-AR gam model using the training set of data
      gam = try(gam(abundance ~ s(temp, k = 10, bs = 'cr') + s(precip, k = precip_k, bs = 'cr'), 
                    select = TRUE, data = train, family = tw,  method = "REML"), silent = TRUE)
    }
    
    if(class(gam)[1] != "try-error"){
      # Predict on test set based on parameterisation of training set
      pred = predict.gam(gam, test, se.fit = TRUE)
      
      # Add lines to plot if desired
      if(plot == TRUE){
        lines(x = as.Date(test$caldates, "%Y-%m-%d"), y = exp(pred$fit), col = "red")
      }
      
      # Record contribution of this test set to the weighted average of MAE
      MAE[i] = sum(abs(exp(pred$fit) - test$abundance)) * nrow(test)
      
      # Add these data points to the total number of included points in the MAE
      pts_included = pts_included + nrow(test)
      
      # Record the mean bias
      MB[i] = sum(exp(pred$fit) - test$abundance)/length(test$abundance)
      
      # Record NMAE
      NMAE[i] = sum(abs(exp(pred$fit) - test$abundance))/sum(log(test$abundance))
    }
    
  }
  
  # Return a vector of the MAE, NMAE, MB, and number of folds used in averaging
  return(c(round(sum(MAE, na.rm = TRUE)/pts_included, 3), round(mean(NMAE, na.rm = TRUE), 3), round(mean(MB, na.rm = TRUE), 3), sum(!is.na(MAE))))
  
}

akaike_weight = function(output_data, lags, i){
  # Find just the Akaike weight of the best fit model
  # Find the numerator: for best fit lag, delta AIC = 0.  exp(-1/2 delta AIC). 
  num = exp(-1/2 * 0) # is equal to 1
  
  # Find the temperature denominator: sum of exp(-1/2 delta AIC) for each lag
  denom = sum(exp(-1/2 * (output_data[i,which(colnames(output_data) %in% lags$temp)] - min(output_data[i,which(colnames(output_data) %in% lags$temp)]))))
  
  # Store in table
  output_data$AIC_wt_temp[i] = round(num/denom, 3) *100
  
  # Find the temperature denominator: sum of exp(-1/2 delta AIC)
  denom = sum(exp(-1/2 * (output_data[i,which(colnames(output_data) %in% lags$precip)] - min(output_data[i,which(colnames(output_data) %in% lags$precip)]))))
  
  # Store in table
  output_data$AIC_wt_precip[i] = round(num/denom, 3) *100
  
  return(output_data)
}

plot_gam_check = function(gam_object){
  
  # Re-formats gam.check() so that diagnostic plots are displayed on one screen
  # From Gavin Simpson on Stack Exchange, who copied from gam.check() source code
  
  # Create 2 x 2 plotting matrix
  par(mfrow=c(2,2))
  
  # Find residuals of the gam fit
  resid <- residuals(gam_object, type = "deviance")
  
  # Predict points
  linpred <- napredict(gam_object$na.action, gam_object$linear.predictors)
  observed.y <- napredict(gam_object$na.action, gam_object$y)
  
  # QQ plot
  qq.gam(gam_object, rep = 0, level = 0.9, type = "deviance", rl.col = 2, 
         rep.col = "gray80", main = gam_object$family$family)
  
  # Histogram of residuals
  hist(resid, xlab = "Residuals", main = "Histogram of residuals")
  
  # Residuals vs linear predictors
  plot(linpred, resid, main = "Resids vs. linear pred.", 
       xlab = "linear predictor", ylab = "residuals")
  
  # Fitted values
  plot(fitted(gam_object), observed.y, xlab = "Fitted Values", 
       ylab = "Response", main = "Response vs. Fitted Values")
  
  # Make sure to run dev.off() after this function
}
