#!/bin/bash

declare -A pidStatsArray  # Associative array to store the read/write operations of each process
declare -A temporaryArray # Temporary array to store the pid and the desired sort method information
declare -a sortedArray   # Array to store the sorted information
declare -a sortedPIDArray  # Array to store the sorted PID information
cT=0;     # -c: process name
uT=0;     # -u: user name
sT=0;     # -s: start time limit
eT=0;     # -e: end time limt
mT=0;     # -m: lower pid number limit
MT=0;     # -M  upper pid number limit
rT=0;     # -r: reverse
wT=0;     # -w: sort by write value
pT=0;     # -p: number of results to display

format() {
    if [[ $1 =~ ^-.*$ ]]; then #if an argument has - at the start of the name exit 
        echo "Error: Argument format invalid -> $1"
        exit 1
    fi
}

function get_read_write_stats() { 
    
    local timetoSleep=$1
    for pid in "${pidArr[@]}"
    do
        pidstats=()
        if (cat /proc/$pid/io > /dev/null 2> /dev/null); then
            
        local cmd=$(ps -p $pid -o comm=)

        local user=$(ps -p $pid -o user=)

        local startTime=$(ps -p $pid -o lstart= | awk '{print $2 " " $3 " " substr($4,1,length($4)-3)}')

        local readStatsBeforeSleep=$(cat /proc/$pid/io | grep rchar | awk '{print $2}')
  
        local writeStatsBeforeSleep=$(cat /proc/$pid/io | grep wchar | awk '{print $2}')
        pidstats+=("$cmd|$pid|$user|$readStatsBeforeSleep|$writeStatsBeforeSleep|")    
    
        pidStatsArray[$pid]=${pidstats[@]}
        fi
    done

    sleep $timetoSleep

    for pid in "${pidArr[@]}"
    do
        if (cat /proc/$pid/io > /dev/null 2> /dev/null); then
        pidstats=${pidStatsArray[$pid]}
        IFS='|' read -r -a pidstattempArr <<< "${pidStatsArray[$pid]}"
        cmd=${pidstattempArr[0]}
        pid=${pidstattempArr[1]}
        user=${pidstattempArr[2]}
        readStatsBeforeSleep=${pidstattempArr[3]}
        writeStatsBeforeSleep=${pidstattempArr[4]}

        local readStatsAfterSleep=$(cat /proc/$pid/io | grep rchar | awk '{print $2}')

        local writeStatsAfterSleep=$(cat /proc/$pid/io | grep wchar | awk '{print $2}')

        local readStats=$(($readStatsAfterSleep - $readStatsBeforeSleep))
        
        local writeStats=$(($writeStatsAfterSleep - $writeStatsBeforeSleep))

        local readRate=$(echo "scale=0; ($readStatsAfterSleep - $readStatsBeforeSleep) / $timetoSleep" | bc)
    
        local writeRate=$(echo "scale=0; ($writeStatsAfterSleep - $writeStatsBeforeSleep) / $timetoSleep" | bc)
    
        pidStatsArray[$pid]="$cmd|$pid|$user|$readStats|$writeStats|$readRate|$writeRate|$startTime"
        fi
    done
}

function Sort_Results() {   
    local rT=$1
    local wT=$2
    
    # if rt = 0, wt = 0, sort by read rate
    if [ $rT -eq 0 ] && [ $wT -eq 0 ]; then
        for pid in "${pidArr[@]}"
        do  
            IFS='|' read -r -a pidstattemp <<< "${pidStatsArray[$pid]}"
            local readRate=$(echo ${pidstattemp[5]})
            temporaryArray[$pid]=$readRate
        done
        sortedArray=($(for pid in "${!temporaryArray[@]}"; do echo "$pid ${temporaryArray[$pid]}"; done | sort -k2 -n -r))
    fi
    
    # wt = 0, rt = 1, sort by reversed read rate
    if [ $rT -eq 1 ] && [ $wT -eq 0 ]; then
        for pid in "${pidArr[@]}"
        do
            IFS='|' read -r -a pidstattemp <<< "${pidStatsArray[$pid]}"
            local readRate=$(echo ${pidstattemp[5]})
            temporaryArray[$pid]=$readRate
        done
        sortedArray=($(for pid in "${!temporaryArray[@]}"; do echo "$pid ${temporaryArray[$pid]}"; done | sort -k2 -n))
    fi

    # wt = 1, rt = 0, sort by write Stats
    if [ $rT -eq 0 ] && [ $wT -eq 1 ]; then
        for pid in "${pidArr[@]}"
        do
            IFS='|' read -r -a pidstattemp <<< "${pidStatsArray[$pid]}"
            local writeRate=$(echo ${pidstattemp[6]})
            temporaryArray[$pid]=$writeRate
        done
        sortedArray=($(for pid in "${!temporaryArray[@]}"; do echo "$pid ${temporaryArray[$pid]}"; done | sort -k2 -n -r))
    fi

    # wt = 1, rt = 1, sort by reversed write Stats
    if [ $rT -eq 1 ] && [ $wT -eq 1 ]; then
        for pid in "${pidArr[@]}"
        do
            IFS='|' read -r -a pidstattemp <<< "${pidStatsArray[$pid]}"
            local writeRate=$(echo ${pidstattemp[4]})
            temporaryArray[$pid]=$writeRate
        done
        sortedArray=($(for pid in "${!temporaryArray[@]}"; do echo "$pid ${temporaryArray[$pid]}"; done | sort -k2 -n ))
    fi
    
    for (( i=0; i < ${#sortedArray[@]}; i=i+2 ))
    do
        sortedPIDArray+=(${sortedArray[$i]})
    done

}

while getopts "c:u:s:e:m:M:p:rw" opt; do
    case $opt in
        c)
            format $OPTARG
            cArg=$OPTARG
            cT=1
            ;;
        u)
            format $OPTARG
            uArg=${OPTARG}
            uT=1
            ;;
        s)
            format $OPTARG
            if [ $eT -eq 1 ]; then
                if [[ $OPTARG > $eArg ]]; then
                    echo "Error: Start time cannot be greater than end time"
                    exit 1
                fi
            fi

            if date -d "$OPTARG" > /dev/null 2> /dev/null; then
                sArg=$OPTARG
                sT=1
            else
                echo "Error: Invalid date for argument -s. Please use the format 'Month Day HH:MM'"
                exit 1
            fi

            sArg=${OPTARG}
            sT=1
            ;;
        e)
            format $OPTARG
            if [ $sT -eq 1 ]; then
                if [[ $OPTARG < $sArg ]]; then
                    echo "Error: End time cannot be less than start time"
                    exit 1
                fi
            fi

            if date -d "$OPTARG" > /dev/null 2> /dev/null; then
                eArg=$OPTARG
                eT=1
            else
                echo "Error: Invalid date for argument -e. Please use the format 'Month Day HH:MM'"
                exit 1
            fi

            eArg=${OPTARG}
            eT=1
            ;;
        m)
            format $OPTARG
            if [ $MT -eq 1 ]; then
                if [ $OPTARG -gt $MArg ]; then
                    echo "Error: Minimum PID cannot be greater than maximum PID"
                    exit 1
                fi
            fi

            if ! [[ $OPTARG =~ ^[0-9]+$ ]]; then
                echo "Error: -m argument must be a number"
                exit 1
            fi
            mArg=${OPTARG}
            mT=1
            ;;
        M)
            format $OPTARG
            if [ $mT -eq 1 ]; then
                if [ $OPTARG -lt $mArg ]; then
                    echo "Error: Maximum PID cannot be less than minimum PID"
                    exit 1
                fi
            fi

            if ! [[ $OPTARG =~ ^[0-9]+$ ]]; then
                echo "Error: -M argument must be a number"
                exit 1
            fi
            MArg=${OPTARG}
            MT=1
            ;;
        p)
            format $OPTARG
            if ! [[ $OPTARG =~ ^[0-9]+$ ]]; then
                echo "Error: -p argument must be a number"
                exit 1
            fi
            pArg=${OPTARG}
            pT=1
            ;;
        r)
            rT=1
            ;;
        w)
            wT=1
            ;;
        \?)
            echo "ERROR: Invalid option: -$OPTARG. Valid Arguments are -c, -u, -s, -e, -m, -M, -p, -r, -w"
            exit 1
            ;;
    esac
done

if [ $# -eq 0 ]; then
    echo "ERROR: No arguments. Sleep_Time mandatory"
    exit 1
fi

if ! [[ $OPTIND -eq $# ]]; then
    echo "ERROR: Sleep needs to be the last argument"
    exit 1
fi

shift $(($OPTIND - 1))

if ! [[ $1 =~ ^[0-9]+$ ]]; then
    echo "ERROR: Invalid Sleep_Time: $1. Sleep_Time must be a number"
    exit 1
fi


pidArr=()

for pid in $(ps -eo pid | tail -n +2)
do
    add=1
    if [ $cT -eq 1 ]; then
        if ! [[ $(ps -p $pid -o comm=) =~ ^$cArg$ ]]; then
            add=0
        fi
    fi
    if [ $uT -eq 1 ]; then
        if ! [[ $(ps -p $pid -o user=) =~ ^$uArg$ ]]; then
            add=0
        fi
    fi
    if [ $sT -eq 1 ]; then
        if [[ $(ps -p $pid -o lstart= | awk '{print $2 " " $3 " " substr($4,1,length($4)-3)}') < $sArg ]]; then
            add=0
        fi
    fi
    if [ $eT -eq 1 ]; then
        if [[ $(ps -p $pid -o lstart= | awk '{print $2 " " $3 " " substr($4,1,length($4)-3)}') > $eArg ]]; then
            add=0
        fi
    fi
    if [ $mT -eq 1 ]; then
        if [[ $pid -lt $mArg ]]; then
            add=0
        fi
    fi
    if [ $MT -eq 1 ]; then
        if [[ $pid -gt $MArg ]]; then
            add=0
        fi
    fi
    if [ $add -eq 1 ]; then
        pidArr+=($pid)
    fi
done

get_read_write_stats $1


Sort_Results $rT $wT

printf "%-30s %-20s %20s %20s %20s %20s %20s %20s\n" "COMM" "USER" "PID" "READB" "WRITEB" "RATER" "RATEW" "DATE"


counter=0;
for i in "${sortedPIDArray[@]}"
do  
    if [ $pT -eq 1 ]; then
        if [ $counter -eq $pArg ]; then
            break
        fi
    fi
    if [ -z "${pidStatsArray[$i]}" ]; then  #some processes may have blank stats
        continue
    fi
    IFS='|' read -r -a pidstatprintarr <<< "${pidStatsArray[$i]}"
    printf "%-30s %-20s %20s %20s %20s %20s %20s %20s\n" "${pidstatprintarr[0]}" "${pidstatprintarr[2]}" "${pidstatprintarr[1]}" "${pidstatprintarr[3]}" "${pidstatprintarr[4]}" "${pidstatprintarr[5]}" "${pidstatprintarr[6]}" "${pidstatprintarr[7]}"
    ((counter=counter+1))
done


