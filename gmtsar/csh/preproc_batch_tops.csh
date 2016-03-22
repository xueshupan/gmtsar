#!/bin/csh -f
#       $Id$
#
# Xiaohua(Eric) Xu, Feb 26 2016
# Take previous code, make it work with multiple frames
# Take previous code, make it work with bursts mismatch

# Preprocess and align tops image stacks
# used for time series analysis

# Xiaohua(Eric) Xu, Jan 19 2016
#

  if ($#argv != 3) then
    echo ""
    echo "Usage: preproc_tops_batch.csh data.in dem.grd mode"
    echo "  preprocess and align a set of tops images in data.in, precise orbits required"
    echo ""
    echo "  format of data.in:"
    echo "    image_name:orbit_name"
    echo ""
    echo "  example of data.in"
    echo "    s1a-iw1-slc-vv-20150626...001:s1a-iw1-slc-vv-20150626...001:s1a-iw1-slc-vv-20150626...001:S1A_OPER_AUX_POEORB_V20150601_20150603.EOF"
    echo "    s1a-iw1-slc-vv-20150715...001:s1a-iw1-slc-vv-20150715...001:s1a-iw1-slc-vv-20150715...001:S1A_OPER_AUX_POEORB_V20150625_20150627.EOF"
    echo ""
    echo "  outputs:"
    echo "    baseline.ps align_table.ra (contains info for precise geomatric alignment)"
    echo "    *.PRM *.LED *.SLC(mode 2)"
    echo ""
    echo "  Note:"
    echo "    The names must be in time order in each line to be stitched together"
    echo ""
    exit 1
  endif

  # set up some parameters
  set mode = $3
  set sl = `echo "1"`
  
  # sample the dem
  if ($mode == 2) then
    gmt grdfilter $2 -D2 -Fg2 -I12s -Gflt.grd
    gmt grd2xyz --FORMAT_FLOAT_OUT=%lf flt.grd -s > topo.llt
  endif

  # first line is the super-master, all images aligned to it
  set master = `awk -F: 'NR==1 {print $1}' $1 | awk '{ print "S1A"substr($1,16,8)"_"substr($1,25,6)"_F"substr($1,7,1)}'` 
  set mmaster = `awk -F: 'NR==1 {print $1}' $1 | awk '{ print "S1A"substr($1,16,8)"_ALL_F"substr($1,7,1)}'`
  # clean up a little bit
  rm baseline_table.dat *.PRM* *.SLC *.LED tmp*

  # loop over all the acquisitions
  foreach line (`awk '{print $0}' $1`)
    # record the first one as the stem_master
    set stem_master = `echo $line | awk -F: '{print $1}' | awk '{ print "S1A"substr($1,16,8)"_"substr($1,25,6)"_F"substr($1,7,1)}'`
    set m_stem_master = `echo $line | awk -F: '{print $1}' | awk '{ print "S1A"substr($1,16,8)"_ALL_F"substr($1,7,1)}'`
    if($mode == 1) then

      # for mode 1, generate baseline_plots
      set image = `echo $line | awk -F: '{print $1}'`
      set orbit = `echo $line | awk -F: '{print $NF}'`
     
      # generate prms and leds
      make_s1a_tops $image.xml $image.tiff $m_stem_master 0
      ext_orb_s1a $m_stem_master.PRM $orbit $m_stem_master
      
      # get the height and baseline info
      cp $m_stem_master.PRM junk1
      calc_dop_orb junk1 junk2 0 0
      cat junk1 junk2 > $m_stem_master.PRM

      baseline_table.csh $mmaster.PRM $m_stem_master.PRM >> baseline_table.dat
      baseline_table.csh $mmaster.PRM $m_stem_master.PRM GMT >> table.gmt

      # clean up the mess
      rm junk1 junk2
    else if($mode == 2) then
      # for mode 2, stitch and align all the images

      # find the files to be stitched
      echo $line | awk -F: '{for (i=1;i<NF;i++) print $i}' > tmp.filelist
      set orbit = `echo $line | awk -F: '{print $NF}'`

      if (-f tmp.stitchlist) then 
        rm tmp.stitchlist
      endif
      set nfiles = `wc -l tmp.filelist | awk '{print $1}'`
      set tmp_da = 0

      # loop over all the files in this line
      rm *par*
      foreach file (`awk '{print $0}' tmp.filelist`)
        # generate prms and leds
        set stem = `echo $file | awk '{ print "S1A"substr($1,16,8)"_"substr($1,25,6)"_F"substr($1,7,1)}'`
        
        # get images aligned
        if($sl == 1) then
          # sl=1 means processing the super_master image, simpley generate images and stitch them together
          make_s1a_tops $file.xml $file.tiff $stem 1
          ext_orb_s1a $stem.PRM $orbit $stem
          echo $stem >> tmp.stitchlist
        else
          # sl>1 measn processing slave images, point-by-point alignment and corregistration is required 
          make_s1a_tops $file.xml $file.tiff $stem 0
          ext_orb_s1a $stem.PRM $orbit $stem

          # compute the time difference between first frame and the rest frames
          set t1 = `grep clock_start $stem_master.PRM | grep -v SC_clock_start | awk '{printf("%.13f", $3)}'`
          set t2 = `grep clock_start $stem.PRM | grep -v SC_clock_start | awk '{printf("%.13f", $3)}'`
          set prf = `grep PRF $stem_master.PRM | awk '{printf("%.6f",$3)}'`
          set nl = `echo $t1 $t2 $prf | awk '{printf("%d",($2-$1)*$3*86400.0+0.2)}'`
	  echo "Shifting the master PRM by $nl lines..."
	  cp $master.PRM tmp.PRM

          # shift the super-master's PRM based on $nl so SAT_llt2rat gives precise estimate. 
	  set ttmp = `grep clock_start tmp.PRM | grep -v SC_clock_start | awk '{print $3}' | awk '{printf ("%.12f",$1+'$nl'/'$prf'/86400.0)}'`
	  update_PRM.csh tmp.PRM clock_start $ttmp
	  set ttmp = `grep clock_stop tmp.PRM | grep -v SC_clock_stop | awk '{print $3}' | awk '{printf ("%.12f",$1+'$nl'/'$prf'/86400.0)}'`
          update_PRM.csh tmp.PRM clock_stop $ttmp
          set ttmp = `grep SC_clock_start tmp.PRM | awk '{print $3}' | awk '{printf ("%.12f",$1+'$nl'/'$prf'/86400.0)}'`
          update_PRM.csh tmp.PRM SC_clock_start $ttmp
          set ttmp = `grep SC_clock_stop tmp.PRM | awk '{print $3}' | awk '{printf ("%.12f",$1+'$nl'/'$prf'/86400.0)}'`
          update_PRM.csh tmp.PRM SC_clock_stop $ttmp

          # compute whether there are any image offset
          if ($tmp_da == 0) then
            set tmp_am = `head topo.llt | awk 'NR == 1 {print $0}' | SAT_llt2rat tmp.PRM 1 | awk '{print $2}'`
            set tmp_as = `head topo.llt | awk 'NR == 1 {print $0}' | SAT_llt2rat $stem.PRM 1 | awk '{print $2}'`
            set tmp_da = `echo $tmp_am $tmp_as | awk '{printf("%d",$2-$1)}'`
          endif

          # in case the images are offset by more than a burst, shift the super-master's PRM again so SAT_llt2rat gives precise estimate
          if ($tmp_da > -1000 && $tmp_da < 1000) then
            cp tmp.PRM junk1
            calc_dop_orb junk1 junk2 0 0
            cat junk1 junk2 > tmp.PRM
            set earth_radius = `grep earth_radius tmp.PRM | awk '{print $3}'`
            cp $stem.PRM junk1
            calc_dop_orb junk1 junk2 $earth_radius 0
            cat junk1 junk2 > $stem.PRM
            rm junk1 junk2

            SAT_llt2rat tmp.PRM 1 < topo.llt > tmpm.dat &
            SAT_llt2rat $stem.PRM 1 < topo.llt > tmp1.dat &
	    wait
          else
            echo "Modifying master PRM by $tmp_da lines..."
            set prf = `grep PRF tmp.PRM | awk '{print $3}'`
            set ttmp = `grep clock_start tmp.PRM | grep -v SC_clock_start | awk '{print $3}' | awk '{printf ("%.12f",$1-'$tmp_da'/'$prf'/86400.0)}'`
            update_PRM.csh tmp.PRM clock_start $ttmp
            set ttmp = `grep clock_stop tmp.PRM | grep -v SC_clock_stop | awk '{print $3}' | awk '{printf ("%.12f",$1-'$tmp_da'/'$prf'/86400.0)}'`
            update_PRM.csh tmp.PRM clock_stop $ttmp
            set ttmp = `grep SC_clock_start tmp.PRM | awk '{print $3}' | awk '{printf ("%.12f",$1-'$tmp_da'/'$prf'/86400.0)}'`
            update_PRM.csh tmp.PRM SC_clock_start $ttmp
            set ttmp = `grep SC_clock_stop tmp.PRM | awk '{print $3}' | awk '{printf ("%.12f",$1-'$tmp_da'/'$prf'/86400.0)}'`
            update_PRM.csh tmp.PRM SC_clock_stop $ttmp

            cp tmp.PRM junk1
            calc_dop_orb junk1 junk2 0 0
            cat junk1 junk2 > tmp.PRM
            cp $stem.PRM junk1
            calc_dop_orb junk1 junk2 0 0
            cat junk1 junk2 > $stem.PRM
            rm junk1 junk2
            
            #SAT_llt2rat tmp.PRM 1 < topo.llt > tmp_tmp.dat &
            SAT_llt2rat tmp.PRM 1 < topo.llt > tmpm.dat &
            SAT_llt2rat $stem.PRM 1 < topo.llt > tmp1.dat &
            wait
            #echo "Restoring $tmp_da lines to master ashifts..."
            #awk '{printf("%.6f %.6f %.6f %.6f %.6f\n",$1,$2-'$tmp_da',$3,$4,$5)}' tmp_tmp.dat > tmpm.dat
          endif

          # get r, dr, a, da, SNR table to be used by fitoffset.csh
          paste tmpm.dat tmp1.dat | awk '{printf("%.6f %.6f %.6f %.6f %d\n", $1, $6-$1, $2, $7-$2, "100")}' > tmp.dat
          set rmax = `grep num_rng_bins $stem.PRM | awk '{print $3}'`
          set amax = `grep num_lines $stem.PRM | awk '{print $3}'`
          awk '{if($1 > 0 && $1 < '$rmax' && $3 > 0 && $3 < '$amax') print $0 }' < tmp.dat > offset.dat
         
          # prepare the offset parameters for the stitched image 
          #if ($stem == $stem_master) then
            #set tmp_rec = `echo $amax $nfiles | awk '{printf("%d", $1*$2-120*($2-1))}'`
          if ($tmp_da > -1000 && $tmp_da < 1000) then
            awk '{printf("%.6f %.6f %.6f %.6f %d\n", $1, $2, $3+'$nl', $4, $5)}' < offset.dat >> par_tmp.dat
          else
            awk '{printf("%.6f %.6f %.6f %.6f %d\n", $1, $2, $3+'$nl'-'$tmp_da', $4+'$tmp_da', $5)}' < offset.dat >> par_tmp.dat
          endif
            #awk '{if($1 > 0 && $1 < '$rmax' && $3 > 0 && $3 < '$tmp_rec') print $0 }' < tmp.dat > par_tmp_sm.dat
            #paste tmpm.dat tmp1.dat | awk '{printf("%.6f %.6f %.6f %.6f %d\n", $1, $6-$1, $2, $7-$2, "100")}' > tmp.dat
          #awk '{if($1 > 0 && $1 < '$rmax' && $3 > 0 && $3 < '$amax') printf("%.6f %.6f %.6f %.6f %d\n", $1, $2, $3+'$nl', $4, $5)}' < tmp.dat >> par_tmp_m.dat
            #awk '{if($1 > 0 && $1 < '$rmax' && $3 > 0 && $3 < '$tmp_rec') print $0 }' < tmp.dat > par_tmp.dat
            #awk '{if($1 > 0 && $1 < '$rmax' && $3 > 0 && $3 < '$amax') print $0 }' < tmp.dat > par_tmp.dat
          #endif

          # prepare the rshift and ashift look up table to be used by make_s1a_tops
          awk '{ printf("%.6f %.6f %.6f \n",$1,$3,$2) }' < offset.dat > r.xyz
          awk '{ printf("%.6f %.6f %.6f \n",$1,$3,$4) }' < offset.dat > a.xyz
          gmt blockmedian r.xyz -R0/$rmax/0/$amax -I8/4 -r -bo3d > rtmp.xyz
          gmt blockmedian a.xyz -R0/$rmax/0/$amax -I8/4 -r -bo3d > atmp.xyz
          gmt surface rtmp.xyz -bi3d -R0/$rmax/0/$amax -I8/4 -Grtmp.grd -T0.5 -N1000  -r &
          gmt surface atmp.xyz -bi3d -R0/$rmax/0/$amax -I8/4 -Gatmp.grd -T0.5 -N1000  -r &
          wait
          gmt grdmath rtmp.grd FLIPUD = r.grd
          gmt grdmath atmp.grd FLIPUD = a.grd          

          # generate the image with point-by-point shifts
          make_s1a_tops $file.xml $file.tiff $stem 1 r.grd a.grd
         
          # in case theere is a shift caused by image offset, record it from updated ashift by make_s1a_tops
          #if ($stem == $stem_master) then
          #  set bshift = `grep ashift $stem_master.PRM | awk '{print $3}'`
          #endif
          
          # in case the shift caused by image offset are not uniform, resamp the lines different, 
          # so later stitched images has a uniform shift to be resamped
          #set ashift = `grep ashift $stem.PRM | awk '{print $3}'`
          #if ($ashift != $bshift) then
          #  cp $stem.PRM $stem.PRM_tmp
          #  set tmp_shift = `echo $ashift $bshift | awk '{printf("%d",$1-$2)}'`
          #  update_PRM.csh $stem.PRM_tmp ashift 0
          #  update_PRM.csh $stem.PRM ashift $tmp_shift
          #  echo "Modifying image to match the bshift...($tmp_shift)"
          #  resamp $stem.PRM_tmp $stem.PRM $stem.PRMresamp $stem.SLCresamp 1
          #  mv $stem.PRMresamp $stem.PRM
          #  mv $stem.SLCresamp $stem.SLC
          #endif
 
          # need to update shift parameter so stitch_tops will know how to stitch
          fitoffset.csh 3 3 offset.dat >> $stem.PRM
          #fitoffset.csh 1 1 offset.dat >> $stem.PRM

          echo $stem >> tmp.stitchlist
        endif
      end
      
      # get the name for stitched file
      set stem = `echo $line | awk -F: '{print $1}' | awk '{ print "S1A"substr($1,16,8)"_ALL_F"substr($1,7,1)}'`
 
      # stitch images together and get the precise orbit
      stitch_tops tmp.stitchlist $stem
      ext_orb_s1a $stem.PRM $orbit $stem

      # for images except the super-master
      if ($sl != 1) then    
        cp $stem.PRM $stem.PRM0
        #if ($bshift != 0) echo "Updated shift caused by burst offset is $bshift"
        if ($tmp_da > -1000 && $tmp_da < 1000) then
          update_PRM.csh $stem.PRM ashift 0
        else
          update_PRM.csh $stem.PRM ashift $tmp_da
          echo "Restoring $tmp_da lines shift to the image..."
        endif
        update_PRM.csh $stem.PRM rshift 0
        
        resamp $mmaster.PRM $stem.PRM $stem.PRMresamp $stem.SLCresamp 1
        mv $stem.PRMresamp $stem.PRM
        mv $stem.SLCresamp $stem.SLC 
        #set swath = `echo $line | awk -F: '{print $1}' | awk '{ print substr($1,7,1)}'`

        # don't know why I was doing this...
        #if ($swath == 2) then
        #  echo "Updated parameters in slave's coordinates"
        #  fitoffset.csh 3 3 par_tmp_s.dat >> $stem.PRM
        #else
        #  echo "Updated parameters in master's coordinates"
        #  fitoffset.csh 3 3 par_tmp_m.dat >> $stem.PRM
        #endif

        #fitoffset.csh 3 3 par_tmp_s.dat >> $stem.PRM
        fitoffset.csh 3 3 par_tmp.dat >> $stem.PRM
      endif
       
       cp $stem.PRM junk1
       calc_dop_orb junk1 junk2 $earth_radius 0
       cat junk1 junk2 > $stem.PRM
       rm junk1 junk2
       set sl = `echo "2"`
    endif
  end

  # for mode 1, plot the time-baseline figure
  if($mode == 1) then
    awk '{print 2014+$1/365.25,$2,$7}' < table.gmt > text
    set region = `gmt gmtinfo text -C | awk '{print $1-0.5, $2+0.5, $3-50, $4+50}'`
    gmt pstext text -JX8.8i/6.8i -R$region[1]/$region[2]/$region[3]/$region[4] -D0.2/0.2 -X1.5i -Y1i -K -N -F+f8,Helvetica+j5 > baseline.ps
    awk '{print $1,$2}' < text > text2
    gmt psxy text2 -Sp0.2c -G0 -R -JX -Ba0.5:"year":/a50g00f25:"baseline (m)":WSen -O >> baseline.ps
    rm text text2 table.gmt
  endif

  # clean up a little bit
  if($mode == 2) rm tmp* topo.llt flt.grd atmp* rtmp*
