#!/bin/bash

FILE="test/LiquidStaking.js"
case "$(uname -s)" in
   Darwin)
     # Reduce maxNumServices from 100 to 10
     sed -i.bu "s/maxNumServices = 100/maxNumServices = 10/g" $FILE
     # Reduce timeForEmission from 30 days to 7 days
     sed -i.bu "s/timeForEmissions = oneDay * 30/timeForEmissions = oneDay * 7" $FILE
     ;;

   Linux)
     # Reduce maxNumServices from 100 to 10
     sed -i "s/maxNumServices = 100/maxNumServices = 10/g" $FILE
     # Reduce timeForEmission from 30 days to 7 days
     sed -i "s/timeForEmissions = oneDay * 30/timeForEmissions = oneDay * 7" $FILE
     ;;

   *)
     echo "Other OS"
     ;;
esac

