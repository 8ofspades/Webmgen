#!/bin/bash
set -x

OPTIND=1
IFS=$'\n'
snd=""
flag=false
subFlag=false
strm=""
timeFlag=false
show_help (){
    echo "Custom webm generator using ffmpeg \n"
    echo "Example: ./WebmGen.sh -i input.mkv -a 92 -s 8000 -b 00:02:30 -e 00:03:10 -o output"
    echo "Options:"
    echo "-h = help (this menu)"
    echo "-i = File input"
    echo "-w = Desired file width (pixels)"
    echo "-a = audio bitrate (using vorbis)"
    echo "-s = desired file size in kilobytes"
    echo "-N = if used, disables audio"
    echo "-b = video start time, uses HH:MM:ss.ms format"
    echo "-e = video end time, format is the same as -b"
    echo "-o = File output in kilobytes (webm using libvpx-vp9)"
    echo "-C = Multiple outputs (Makes a 8MB and 4MB file with sound and a 3MB file without sound)"
    echo "-t = Burn in subtitles"
    echo "-v = vp9 encoding"
}

#Options Menu
while getopts ":hi:o:a:s:NCtvb:w:e:" opt; do
    case $opt in 
    h)
        show_help
	exit 0
	;;
    i)
	input=$OPTARG
	;;
    o)
	output=$OPTARG
	;;
    a)
	Abr=$OPTARG
	;;
    s)
	fileSize=$OPTARG
	;;
    N)
	snd="-an"
	;;
    b)  
	start=$OPTARG
	timeFlag=true
	;;
    e)
	end=$OPTARG
	;;
    w)
	width=$OPTARG
	;;
    C)
	flag=true
	;;
    t)
        subFlag=true
	;;
    v)
        strm="-vp9"
	;;
    esac
done

Run_ffmpeg (){
    #find bitrate

    fileSize=$1
    width=$2
    tag=$3
    stream=$4
    abr=$5
    sound=$6


    echo "fileSize = $fileSize"
    echo "width = $width"
    echo "Filetag = $tag"
    echo "Sound On/Off  = $sound"
    echo "Stream = $stream"
    echo "Abr = $abr"

    if [ $timeFlag = "true" ]
    then
	StartTimes=($(echo $start | sed s/:/\\n/g))
	EndTimes=($(echo $end | sed s/:/\\n/g))
	Time=($(echo "${EndTimes[0]}*3600-${StartTimes[0]}*3600+${EndTimes[1]}*60-${StartTimes[1]}*60+${EndTimes[2]}-${StartTimes[2]}" | bc))
    else
	Time=$(ffprobe -loglevel 16 -i $input -show_format -v quiet | sed -n 's/duration=//p')
	start="00:00:00"
	end=$Time

    fi

    Vbr=$(echo "((8.192*$fileSize)/$Time-$abr)/1" | bc)

    #troubleshooting
    echo "Total Time = $Time seconds"
    echo "Video Bitrate = ${Vbr}k"
    
    if [ $subFlag = "true" ]
    then
	filter=", subtitles=$input"
#	ffmpeg -loglevel 16 -y -i $input -ss $start -to $end ${output}".ass"
#	filter=", ass=${output}.ass"
    else
	filter=""
#	multiThreading=" -threads 8 -tile-columns 6 -frame-parallel 0"
    fi

    #First Pass
    echo "FIRST PASS"
    echo $filter
    ffmpeg -loglevel 16 -y -i $input -c:v libvpx$stream -pass 1 -speed 4 -ss $start -to $end -lag-in-frames 25 -frame-parallel 0 -vf "scale=$width:-1:flags=lanczos$filter" -b:v ${Vbr}k -sn -f webm /dev/null

    #Second Pass
    echo "SECOND PASS"
    echo $filter
    ffmpeg -loglevel 16 -y -i $input -c:v libvpx$stream -pass 2 -speed 1 -ss $start -to $end -c:a libvorbis -lag-in-frames 25 -frame-parallel 0 -vf "scale=$width:-1:flags=lanczos$filter" -b:v ${Vbr}k -b:a ${abr}k $sound -sn -f webm ${output}${tag}".webm"
}

CheckSize (){
    Tfs=$(ffprobe -loglevel 16 -v error quiet -show_entries format=size -of default=noprint_wrappers=1:nokey=1 ${output}${tag}".webm")
    Afs=$(echo "(($Tfs*.953674/1000)*abr/Vbr)/(1+abr/Vbr)" | bc)
    extrafs=$(echo "$fileSize - Vfs - Afs" | bc)
    extrabr=$(echo "extrafs/Time" | bc)
    Vbr=$(echo "extrabr+Vbr" | bc)
    echo "$Vbr"
}

if [ $flag = "true" ]
then
    Run_ffmpeg 12000 960 ""  "-vp9" $Abr ""
    Run_ffmpeg 4000 540 "[Small]"  "" $Abr ""
    Run_ffmpeg 3000 540 "[noAudio]" "" 0 "-an"
    rm ${output}".ass"
else
    Run_ffmpeg "$fileSize" "$width" "" "$strm" "$Abr" "$snd"
fi
