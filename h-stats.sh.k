####################################################################################
###
### casper-miner
###
### Hive integration: BaD
###
####################################################################################

#!/usr/bin/env bash

#######################
# MAIN script body
#######################

CUSTOM_DIR=$(dirname "$BASH_SOURCE")
source $CUSTOM_DIR/h-manifest.conf

stats_raw=`cat $CUSTOM_LOG_BASENAME.log | grep -w "hashrate" | tail -n 1 `

#Calculate miner log freshness

maxDelay=120
time_now=`date +%T | awk -F: '{ print ($1 * 3600) + $2*60 + $3 }'`
time_rep=`echo $stats_raw | awk -FT '{print $2}' | awk -FZ '{print $1}' | awk -F: '{ print (($1+1)*3600) + $2*60 + $3}'`
diffTime=`echo $((time_now-time_rep)) | tr -d '-'`

if [ "$diffTime" -gt "$maxDelay" ]; then
        total_hashrate=`echo $stats_raw | awk '{print $7}' | cut -d "." -f 1,2 --output-delimiter='' | sed 's/$/0/'`

    if [[ $stats_raw == *"Ghash"* ]]; then
        total_hashrate=$(($total_hashrate*1000))
    fi

## Detect hash on GPU ask Power
   LOAD_LIMIT=5
   khs=$total_hashrate
   stats=0
   gpu_stats=$(< $GPU_STATS_JSON)
   readarray -t gpu_stats < <( jq --slurp -r -c '.[] | .busids, .brand, .temp, .fan, .power, .load | join(" ")' $GPU_STATS_JSON 2>/dev/null)
   busids=(${gpu_stats[0]})
   brands=(${gpu_stats[1]})
   temps=(${gpu_stats[2]})
   fans=(${gpu_stats[3]})
   power=(${gpu_stats[4]})
   load=(${gpu_stats[5]})

   count=${#busids[@]}
   total_power=1

   for(( i=0; i<count; i++)); do
      [[ ${load[i]} -gt $LOAD_LIMIT ]] && total_power=$(( total_power + power[i] ))
   done
   hash_arr=()
   busid_arr=()
   fan_arr=()
   temp_arr=()
   for(( i=0; i < count; i++ )); do
      [[ "${brands[i]}" == "cpu" ]] && continue
      [[ "${busids[i]}" =~ ^([A-Fa-f0-9]+): ]]
      busid_arr+=( $((16#${BASH_REMATCH[1]})) )
      temp_arr+=(${temps[i]})
      fan_arr+=(${fans[i]})
      [[ ${load[i]} -gt $LOAD_LIMIT ]] && hash=$(( khs*power[i]/total_power/1000 )) || hash=0
      hash_arr+=($hash)
   done
   hash_json=`printf '%s\n' "${hash_arr[@]}" | jq -cs '.'`
   bus_numbers=`printf '%s\n' "${busid_arr[@]}"  | jq -cs '.'`
   fan_json=`printf '%s\n' "${fan_arr[@]}"  | jq -cs '.'`
   temp_json=`printf '%s\n' "${temp_arr[@]}"  | jq -cs '.'`

# found
ac=$(grep -c "block submitted successfully" $CUSTOM_LOG_BASENAME.log 2>/dev/null)
rj=$(grep -c -i "Failed submitting block" $CUSTOM_LOG_BASENAME.log 2>/dev/null)

# uptime
start_time=`stat -c %Y $CUSTOM_CONFIG_FILENAME 2>/dev/null` &&
uptime=$((`date +%s` - $start_time)) || uptime=

##

        stats=$(jq -nc \
                --argjson hs "$hash_json" \
                --argjson temp "$temp_json" \
                --argjson fan "$fan_json" \
                --arg uptime "$uptime" \
                --arg ver "$CUSTOM_VERSION" \
                --arg ths "$total_hashrate" \
                --arg ac "$ac" --arg rj "$rj" \
                --argjson bus_numbers "$bus_numbers" \
                '{ hs: $hs, hs_units: "mhs", temp: $temp, "fan": $fan, "uptime": $uptime,  ar: [$ac, $rj], algo : "heavyhash", ver:$ver, "bus_numbers":$bus_numbers}')
        khs=$total_hashrate
else
  khs=0
  stats="null"
fi

[[ -z $khs ]] && khs=0
[[ -z $stats ]] && stats="null"
