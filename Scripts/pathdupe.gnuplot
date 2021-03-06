set terminal png large size 600,600
set datafile separator ","
set output "pathdupe.png"
#set grid
#set key off
set timestamp ""
set key default
set key box
set key ins vert
set key left top
set xlabel "Path index"
set ylabel "Duplicate count"
set size ratio 1

set style line 1 lc rgb '#666688' pt 6 ps 0.8
set style line 2 lc rgb '#BB0000' pt 7 ps 1.4

#set xrange [0:0.5]
#set yrange [0:0.5]
#set object 1 circle at 0.5,0 size 0.5 behind
plot \
  "Data/pathdupe.csv" with points ls 1
quit
