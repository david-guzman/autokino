#!/bin/bash

# AutoKino for Linux v0.1
# by David Guzman david.a.guzman@gmail.com
# Linux BASH port from AUTOKINO.bat script written by mandi@lomography.com

echo
echo "AutoKino for Linux (version 0.1)"
echo "by David Guzman david.a.guzman@gmail.com"
echo "BASH port from AUTOKINO.bat script written by mandi@lomography.com"
echo
echo "Note: This shell script requires ImageMagick and ffmpeg in the PATH to work"
echo
echo "Usage ./autokino.sh [dir] - dir is the directory containing the scanned image strips, defaults to current directory"
echo

# variables
STARTTIME=`date`
IM_HOME=/usr
IDENTIFY=$IM_HOME/bin/identify
CONVERT=$IM_HOME/bin/convert
GREP=/bin/grep
FFMPEG=/usr/bin/ffmpeg
WDIR="."
START_WITH=0
CROP_COUNT=0

# functions
function Checkagain {
    # recalculating average lightness of crop area
    SUM_CROP=0
    echo "checking for dark forces"
    for (( K=$1 ; K<=$3 ; K++ )) ; do
        let SUM_CROP="${SUM_CROP} + ${ARR[K]}"
    done

    let MIDCROP="${SUM_CROP}/$3"

   if [ $MIDCROP -ge 20 ] ; then
  	BNAME=`basename $4 .jpg`
		IDX=`printf "%03d" $5`
      echo "another subcrop found, number $6 in ${BNAME}_$5"
		$CONVERT $4 -crop ${MAN_CROP_W}x${ORIGINAL_Y}+$1+${CROP_POS_Y} -rotate 90 -colorspace sRGB frames/${BNAME}_${IDX}_$6.jpg
   fi

    if [ $MIDCROP -lt 20 ] ; then
        echo "too dark for proper image, crop manually if necessary"
    fi
}

function Checkratio {
	#checking if the ratio of probable image makes sense at all
    let MAN_CROP_W="$2*10/28"
    for (( E=1 ; E<=$CROP_COUNT ; E++ )) ; do
        echo -n "Crop detected $E/$CROP_COUNT ${CSTART[E]} - ${CSTOP[E]}"
        let RAT="${2}*100/(${CSTOP[E]} - ${CSTART[E]})"
        let CROP_POS_X="${CSTART[E]} + 2"
        let CROP_W="${CSTOP[E]} - ${CSTART[E]} - 4"
        # checking the various fuzzy ratio ranges
        # needs some improvement and cleaning up here
        if [ "$RAT" -ge 260 ] && [ "$RAT" -le 360 ] ; then
            echo " ... seems OK"

            $CONVERT $1 -crop ${CROP_W}x${ORIGINAL_Y}+${CROP_POS_X}+${CROP_POS_Y} -rotate 90 -colorspace sRGB frames/`basename $1 .jpg`_`printf "%03d" $E`.jpg
        fi

        if [ "$RAT" -gt 360 ] ; then echo "small image" ; fi

        # severe overlap separation
        if [ "$RAT" -lt 260 ] ; then
            echo "... severe overlapping detected, initialising extended cropping routine..."
            let CROPSN = "${CROP_W}/${MAN_CROP_W} + 1"
            let SMALLCROPS = "${CROP_W}/${CROPSN}"
            let CROPDIST = "( ${MAN_CROP_W} + ${SMALLCROPS} ) / 2"
            let STEPS = "${CROPSN} - 1"
            echo "cropping ${CROPSN} parts"

            for (( F=0 ; F<=$STEPS ; F++ )) ; do
                let CROP_POS_XX = "${CROP_POS_X} + $F + ${SMALLCROPS}"
                Checkagain $CROP_POS_XX $CROPDIST $CROP_W $1 $E $F
            done
        fi
    done
}

if [ $# -ne 0 ] ; then
	WDIR=$1
fi

cd $WDIR

# check for sprocket holes
SPH="n"
echo -n "Were the images scanned with sprocket holes? (default n) [y/n]: "
read -n1 SPH
SPE="n"
if [ "$SPH" == "y" ] ; then
	echo
	echo -n "Export with sprocket holes? (default n) [y/n]: "
	read -n1 SPE
fi

# create folder for frames
if [ ! -e "frames" ] ; then
	mkdir frames
fi

echo
echo "Processing image strips"

for A in *.[Jj][Pp][Gg] ; do
	echo

	# getting width and height of the image
	S=`$IDENTIFY -ping -format "%w %h" $A`
	W=`echo $S|cut -f1 -d' '`
	H=`echo $S|cut -f2 -d' '`

	echo -n "Resizing $A to 1px height, adding 1px at the start and the end, if scanned with sprockets, inner part is cropped out : "
	if [ "$SPH" == "n" ] ; then
		$CONVERT $A -normalize -resize ${W}x1! -colorspace HSL -bordercolor black -border 1x0 +repage temp$A
	fi

	if [ "$SPH" == "y" ] ; then
		$CONVERT $A -gravity center -normalize -resize ${W}x1! -colorspace HSL -bordercolor black -border 1x0 +repage temp$A
	fi
	echo "OK"

	ORIGINAL_Y=0
	CROP_POS_Y=0

	if [ "$SPE" == "y" ] ; then
		ORIGINAL_Y=$H
	fi

	if [ "$SPE" == "n" ] ; then
		let ORIGINAL_Y="${H}*7/10"
		let CROP_POS_Y="(${H}-${ORIGINAL_Y})/2"
	fi

	# looping through the 1 pixel high image
	# pixel values are converted to HSL (Hue, Saturation, Lightness) and L-value written to array
	echo -n "Looking for frame borders : "
	declare -a ARR
	C=0
	SUM=0
	for B in `$CONVERT temp$A -colorspace HSL text:|tr -d ' ()'|$GREP -v '^#'|sed -e 's/#.*//'`; do
		ARR[$C]=`echo $B|cut -d',' -f4`
		let "SUM+=${ARR[C]}"
		if [ `expr ${C} % 20` -eq 0 ] ; then echo -n "." ; fi
		let "C+=1"
	done
	echo " OK"

	# calculating average lightness and setting threshold to 1/3.3 lightness
	let AVG="$SUM/${#ARR[@]}"
	let THR="$AVG*10/33"

	FLAG=""
	if [ $THR -lt 17 ] ; then
		THR=17
		FLAG="minimum "
	fi
	echo "setting a ${FLAG}threshold of $THR"

	# signal detection
	# checking values in array, looking for start and stop of probable image area
	# first pixel is always black
	declare -a CSTART
	declare -a CSTOP

	CROP_PIX_START=0
	for (( D=0 ; D < `expr ${#ARR[@]}` ; D++ )); do

		if [ ${ARR[D]} -le $THR ] && [ $START_WITH -eq 1 ] ; then 
			START_WITH=0
			CSTART[$CROP_COUNT]=$CROP_PIX_START
			CSTOP[$CROP_COUNT]=$D
		fi

		if [ ${ARR[D]} -gt $THR ] && [ $START_WITH -eq 0 ] ; then 
			let "CROP_COUNT+=1"
			CROP_PIX_START=$D
			START_WITH=1
		fi

	done

	# sprocket differentiation
	if [ "$SPH" == "n" ] ; then
		echo "Checkratio $A $H"
		Checkratio $A $H
	elif [ "$SPH" == "y" ] ; then
		let NH="$H*7/10"
		Checkratio $A $NH
 	fi

	rm temp$A
done
echo
echo "You can check movieframes now before continuing"

BASE=""
if [ -e "sub" ] ; then
   cd sub/frames
   BASE="../.."
fi

if [ -e "frames" ] ; then
   cd frames
	BASE=".."
fi
echo

echo "Continue now with creation of movie? [y/n]"
read -n1 CREATE

if [ "$CREATE" == "y" ] ; then
   echo "Renaming movie frames"
   FN=0 
   for L in *.jpg ; do
      mv $L `printf "%04d" $FN`.jpg
   	let "FN+=1"
   done

   echo "Movie frames renamed"
   XMAX=2000
   YMAX=1000
   for L in *.jpg ; do
      DIM=`identify -ping -format "%w %h" $L`
      XDIM=`echo ${DIM}|cut -d' ' -f1`
      YDIM=`echo ${DIM}|cut -d' ' -f2`

      if [ "$XDIM" -lt $XMAX ] ; then XMAX=${XDIM} ; fi
   	if [ "$YDIM" -lt $YMAX ] ; then YMAX=${YDIM} ; fi
   done

   echo "make the dimensions even and converting all cropped images to same size"
   echo "essential for ffmpeg to work flawlessly"
   for L in *.jpg ; do
   	mogrify -background black -gravity center -extent ${XMAX}x${YMAX} $L
   done

   # create movie with ffmpeg
   FNAME=`ls *.jpg|head -n1|cut -c1-4`
   $FFMPEG -r 5 -sameq -i %04d.jpg -sameq lomokino_${FNAME}.mp4
   echo "Movie is ready"
fi
