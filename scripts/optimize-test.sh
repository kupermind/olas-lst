#!/bin/bash

FILE="test/LiquidStaking"
case "$(uname -s)" in
   Darwin)
     # Reduce maxNumServices from 100 to 10
     # Reduce timeForEmission from 30 days to 7 days
     sed -e "s/maxNumServices = 100/maxNumServices = 10/g" -e "s/timeForEmissions = 30/timeForEmissions = 7/g" ${FILE}.js > ${FILE}Optimized.js

     ;;

   Linux)
     # Reduce maxNumServices from 100 to 10
     # Reduce timeForEmission from 30 days to 7 days
     sed -e "s/maxNumServices = 100/maxNumServices = 10/g" -e "s/timeForEmissions = 30/timeForEmissions = 7/g" ${FILE}.js > ${FILE}Optimized.js
     ;;

   *)
     echo "Other OS"
     ;;
esac

