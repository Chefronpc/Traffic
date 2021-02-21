#!/usr/bin/perl

#--------Ustawienie stalych uzytkownika-------------------

my $net     = "192.168.0.";			# Adres sieci 
my $if_up   = "enp0s25";			# interface wyjsciowy  -  internet    !!!! z punktu widzenia 
my $if_down = "enp3s7";				#  - || -   wejsciowy  -  LAN         !!!! kontroli pasma
#my $pasmo_in = 12160;				# pasmo wejsciowe glownej kolejki HTB			12160 max dla 100Mbit   7800 Real dla 100Mbit
#my $pasmo_out = 3890;				#pasmo wyjsciowe glównej kolejki HTB
my $pasmo_in = 12800;				# pasmo wejsciowe glownej kolejki HTB
my $pasmo_out = 4000;				#pasmo wyjsciowe glównej kolejki HTB
my $pasmo_max_download = 13160;		# dopuszczalne pasmo wejsciowe do podzialu dla userow
my $pasmo_max_upload = 4096;		#dopuszczalne pasmo wyjsciowe do podzialu dla userow
my $user_max = 52;					# liczba userów
my $wsp_rezerwy_up = 1;				# minimalna ilosc wolnego pasma upload dla usera
									# bez przesylu ( 0,01 - 100 )
my $wsp_rezerwy_down = 1;			#      j.w.      tylko dla  download'u
my $ipt = '/sbin/iptables';			# lokalizacja iptables
my $cykl = 1;						# Czas cyklu  ... sek.
my $cykl_activ = 60;				# Czas aktywnosci usera					
my @activity;						# Tablica aktywnych userów ( nie kasowana , wylacznie modyfikowana )

my @sumadownload;					# Tablica zsumowanego transferu Download
my @sumaupload;						# Tablica zsumowanego transferu Upload
my $fulldownload;					# Całkowity trasfer Download wszystkich użytkowników 
my $fullupload;						# Całkowity trasfer Upload wszystkich użytkowników 

my $start_ip = 11;					# nr hosta w sieci IP pierwszego uzytkownika
									# przy zalozeniu maski podsieci /24
my $tbf_latency_up = 100;			# czas przetrzymywania w kolejce TBF  w [ms] \ _  dla wyjscia
my $tbf_burst_up = 345000;			# wielkosc bufora kolejki TBF w bajtach      /

my $tbf_latency_down = 400;			#  		-||- 			     \ _  dla wejscia
my $tbf_burst_down = 4600000;		#  		-||-			     /

my $show = 1;						# Wyswietlanie informacji  poziomy   <0, 1, 2, 3>

my $traffic_down = 1;				# Wlaczanie kontroli pasma wejsciowego



@lista_komp = ("9m15","9m17","9m13","9m12","9m2","9m5","9m9","9m24","9m30","9m37","9m29","9m11","9m16","9m23","9m34","9m35","7m1","7m5","7m6","7m10","7m12","7m19","7m28","11m1","11m3","11m5","11m7","7m24","11m11","11m15","11m17","11m21","11m25","11m29","11m30","7m7","7m4","9m7","9m18","9m31","???","???","7m5","11m18","9m8","9m5a","9m6","7m3","9m30a","7m16","9m15Wifi","Docker");


#======================================================================================
# Zakladanie kolejek HTB i TBF !!!!!!
# 
#  Kazdy uzytkownik dostaje pasmo startowe upload: 1  KB/s   ( 50KB/s  podzielic przez 50 userów )
#				    oraz download: 10 KB/s   ( 500KB/s      --  || -- 	   )
#======================================================================================

system ("./start.sh");

system ("tc qdisc del dev ".$if_up." root");
system ("tc qdisc del dev ".$if_down." root");

system ("tc qdisc add dev ".$if_up." handle 1: root htb");
system ("tc class add dev ".$if_up." parent 1:1 classid 1:1 htb rate ".$pasmo_out."kbps");

if ( $traffic_down )
{
	system ("tc qdisc add dev ".$if_down." handle 1: root htb");
	system ("tc class add dev ".$if_down." parent 1:1 classid 1:1 htb rate ".$pasmo_in."kbps");
} 

for ( $nr=0; $nr < $user_max; ++$nr )
{
	$pasmo_upload{$nr} = $pasmo_max_upload / $user_max;
	$pasmo_download{$nr} = $pasmo_max_download / $user_max;
    $handle_up = $nr + $start_ip ;          # nr uchwytu z firewalla dla upload'u
    $handle_down = $nr + $start_ip + 300;   # nr uchwytu z firewalla dla download'u
	$classid_up = $nr + $start_ip + 600;	# nr klas dla upload'u
	$classid_down = $nr +$start_ip + 900;	# nr klas dla download'u

	# ============    Upload   ============= #
	system ("tc class add dev ".$if_up." parent 1:1 classid 1:".$classid_up." htb rate ".$pasmo_out."kbps");
	system ("tc qdisc add dev ".$if_up." parent 1:".$classid_up." handle ".$classid_up.": tbf rate ".$pasmo_upload{$nr}."kbps latency ".$tbf_latency_up."ms burst ".$tbf_burst_up);
	system ("tc filter add dev ".$if_up." protocol ip parent 1:0 handle ".$handle_up." fw flowid 1:".$classid_up);

	# ============   Download  ============= #
	if ( $traffic_down )
	{
       	system ("tc class add dev ".$if_down." parent 1:1 classid 1:".$classid_down." htb rate ".$pasmo_in."kbps");       
       	system ("tc qdisc add dev ".$if_down." parent 1:".$classid_down." handle ".$classid_down.": tbf rate ".$pasmo_download{$nr}."kbps latency ".$tbf_latency_down."ms burst ".$tbf_burst_down);
       	system ("tc filter add dev ".$if_down." protocol ip parent 1:0 handle ".$handle_down." fw flowid 1:".$classid_down);
	}
}

#=======================================================================================
# Konfiguracja firewall'a
#=======================================================================================

system ("/etc/rc.d/rc.firewall");


system ("iptables -t mangle -D FORWARD -i ".$if_up." -j STAT >/dev/null 2>&1");
system ("iptables -t mangle -D FORWARD -o ".$if_up." -j STAT >/dev/null 2>&1");
system ("iptables -t mangle -F STAT >/dev/null 2>&1");
system ("iptables -t mangle -X STAT >/dev/null 2>&1");
system ("iptables -t mangle -N STAT");
system ("iptables -t mangle -I FORWARD -o ".$if_up." -j STAT");
system ("iptables -t mangle -I FORWARD -i ".$if_up." -j STAT");

for ( $nr=0; $nr < $user_max; ++$nr )
{
	$ip = $nr + $start_ip;
	$handle_up = $nr + $start_ip;
	$handle_down = $nr + $start_ip + 300; 

	system("iptables -t mangle -A STAT -d ".$net.$ip);
	system("iptables -t mangle -A STAT -s ".$net.$ip);

	system("iptables -t mangle -A POSTROUTING  -s ".$net.$ip." -j MARK --set-mark ".$handle_up);
	
	if ( $traffic_down )
	{
		system("iptables -t mangle -A POSTROUTING  -d ".$net.$ip." -j MARK --set-mark ".$handle_down);
	}
}



#=======================================================================================
# Kasowanie liczników na firewallu
#=======================================================================================

@info = `$ipt -t mangle -L STAT -vnxZ`;
$start = time();

while ( $now-$start < 10 ) { $now = time(); }

$start = time();

# Petla dzialajaca  przez 10 lat    :)

for ($loop=0; $loop < 315360000; ++$loop ) 		#  315360000 sek.  = 10 lat
{
	# ---------------------------- #
	# Oczekiwanie na koniec cyklu  #
	# ---------------------------- #
	while ( $now-$start < $cykl ) { $now = time(); }

	# ==============================================================================================
	# ==============================================================================================

	# --------------- #
	# Poczateki cyklu #
	# --------------- #

	$start = time();

	if ( $show > 0 ) { 
		system ("clear");
	}


	#  my $month = int(`date +%m`);		# niewykorzystywane
	#  my $year = int(`date +%Y`);		# --||--
	#  my $file = "$path/$year$month";	# --||--
	my $now = time();
	my @info;

	my @download;
	my @upload;
	# my @sumadownload
	# my @sumaupload
  
	# Odczytanie danych z firewalla
	@info = `$ipt -t mangle -L STAT -vnxZ`;

	$suma_activ = 0;			# Liczba aktywnych uzytkowników , zerowana na poczatku kazdego cyklu

	foreach my $line (@info)
	{
		chomp($line);
        my $host = "";
        my $bytes = 0;
        my $pkts = 0;


		if($line =~ /^[ ]+([0-9]+)[ ]+([0-9]+).*all.* 0\.0\.0\.0\/0[ ]+([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})/ )
		{
			$line =~ s/^[ ]+([0-9]+)[ ]+([0-9]+).*all.* 0\.0\.0\.0\/0[ ]+([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})/$1 $2 $3/g;
			($pkts, $bytes, $host) = split ' ',$line;

			$nr = substr($host,10,12)-11;	
			$download{$nr} = $bytes/1000;
			$sumadownload{$nr}=$sumadownload{$nr}+$bytes/1000000;
		}
		elsif($line =~ /^[ ]+([0-9]+)[ ]+([0-9]+).*all.* ([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})[ ]+0\.0\.0\.0\/0/ )
		{
			$line =~ s/^[ ]+([0-9]+)[ ]+([0-9]+).*all.* ([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})[ ]+0\.0\.0\.0\/0/$1 $2 $3/g;
			($pkts, $bytes, $host) = split ' ',$line;

			$nr = substr($host,10,12)-11;
			$upload{$nr} = $bytes/1000;
			$sumaupload{$nr}=$sumaupload{$nr}+$bytes/1000000;
		}
	}

#===============================================================
#  Okreslanie aktywnosci uzytkowników 
#===============================================================

	$activ{$nr} = 0;
	$i=$now-$activity{$nr};

	if($i < $cykl_activ ) 
	{ 
		$activ{$nr} = 1; 
		$suma_activ += 0.5;		# dwukrotny przebieg dla 1 usera ( upload i download )
	}

	if($download{$nr} || $upload{$nr})
	{
		$activity{$nr} = $now;
	}


	if ( $suma_activ =~ /\./) {			# Jezeli liczba aktywnych userow nie jest liczba calkowita
		$suma_activ += 0.5;			# 
  	}

  	if ( !$suma_activ  ) {			# Aby nie bylo dzielenia przez 0
		$suma_activ = 1;
  	}

	if ( $show > 1 ) {
		print "   Suma activ :      ".$suma_activ."\n";
	}

  #=======================================================================================
  #	Obliczanie nowych pasm dla userów
  #=======================================================================================
  
  	$suma_pasma_upload = 0;
  	$suma_pasma_download = 0;
  	$suma_upload = 0;
  	$suma_download = 0;
  	$suma_pkt_upload = 0;
  	$suma_pkt_download = 0;
  	$fulldownload=0;
  	$fullupload=0;

	for ( $nr=0; $nr < $user_max; ++$nr ) 
  	{
		if ( $activ{$nr} ) 
		{
	        if ( $download{nr} < 1 ) { $download{nr} = 1 }
                if ( $upload{nr} < 1 ) { $upload{nr} = 1 }

			$suma_upload       += $upload{$nr};
			$suma_pasma_upload += $pasmo_upload{$nr};

			$suma_download       += $download{$nr};
			$suma_pasma_download += $pasmo_download{$nr};

			$pkt_upload[$nr]  = $upload{$nr} / ( $pasmo_upload{$nr} + 1 );
			$suma_pkt_upload += $pkt_upload[$nr];
		
			$pkt_download[$nr]  = $download{$nr} / ( $pasmo_download{$nr} +1 );
			$suma_pkt_download += $pkt_download[$nr];

			if ( $show > 0 ) {
				#print "Host: $lista_komp[$nr] \tDownload: $download{$nr}     \tUpload: $upload{$nr}\n";
				printf ("Host: $lista_komp[$nr] \tDownload: %.0f kB  \tSuma: %.0f MB\tUpload: %.0f kB\tSuma: %.0f MB\n" , $download{$nr}, $sumadownload{$nr}, $upload{$nr}, $sumaupload{$nr} );
			}

#			if ( $show > 0 ) {
#				#print "Host: $lista_komp[$nr] \tDownload: $download{$nr}     \tUpload: $upload{$nr}\n";
#				print "Host: $lista_komp[$nr] \tDownload: $download{$nr}    \tSuma: \t$sumadownload{$nr} \tUpload: $upload{$nr}  \tSuma: \t $sumaupload{$nr} \n";
#			}

		}
	$fulldownload += $sumadownload{$nr};
	$fullupload += $sumaupload{$nr};

	}

	$wolne_pasmo_upload =   $pasmo_max_upload   - $suma_upload;
	$wolne_pasmo_download = $pasmo_max_download - $suma_download;
        
	if ( $wolne_pasmo_upload < 0 ) {		# Jezeli uzytkownicy przekrocza maks. pasmo
		$wolne_pasmo_upload = 0;		# ustawiamy $wolne_pasmo na 0  !!!
	}						# Moze to nastapic dzieki buforowi kolejki TBF

	if ( $wolne_pasmo_download < 0 ) {
		$wolne_pasmo_download = 0;
 	}

	$wsp_zmian_upload   = ( $wolne_pasmo_upload   / $pasmo_max_upload * $wsp_rezerwy_up ) + 1;
	$wsp_zmian_download = ( $wolne_pasmo_download / $pasmo_max_download * $wsp_rezerwy_down ) + 1;

	$sr_pasmo_upload   = $suma_pasma_upload   / $suma_activ;
	$sr_pasmo_download = $suma_pasma_download / $suma_activ;

	$sr_pkt_upload   = $suma_pkt_upload   / $suma_activ;
	$sr_pkt_download = $suma_pkt_download / $suma_activ;

	$uzyty_download = $suma_download / $pasmo_max_download * 100;		# TEMP
	$uzyty_upload = $suma_upload / $pasmo_max_upload * 100 ;		# TEMP

	if ( $show > 0 ) {
		printf ("\n      Suma\tDownload: %.3f GB\t\tSuma\tUpload: %.3f GB\n", $fulldownload/1000, $fullupload/1000 );
  
		printf ("\n      Razem Download: %.3f MB\t\t\tRazem Upload  : %.3f MB\n", $suma_download/1000 , $suma_upload/1000 );
		printf ("      wykorzystanie : %.1f %      \t\twykorzystanie: %.1f %\n\n", $uzyty_download, $uzyty_upload );
	}
	if ( $show > 2 ) {
		print "Wolne pasmo download : $wolne_pasmo_download\tWolne pasmo upload : $wolne_pasmo_upload\n";
		print "   Suma pkt download : $suma_pkt_download\t    Suma pkt upload : $suma_pkt_upload\n";
		print "Srednia pkt download : $sr_pkt_download\t Srednia pkt upload : $sr_pkt_upload\n";
		print " Wsp. zmian download : $wsp_zmian_download\t  Wsp. zmian upload : $wsp_zmian_upload\n";
	}

	$suma_posrednie_upload   = 0;
	$suma_posrednie_download = 0;

	for ( $nr=0; $nr < $user_max; ++$nr )
	{
		if ( $activ{$nr} )
		{
			$posrednie_upload{$nr} = $upload{$nr} + $sr_pasmo_upload * ( $pkt_upload{$nr} + $sr_pkt_upload )  / $wsp_zmian_upload;

			$posrednie_download{$nr} = $download{$nr} + $sr_pasmo_download * ( $pkt_download{$nr} + $sr_pkt_download ) / $wsp_zmian_download;

			$suma_posrednie_upload   += $posrednie_upload{$nr};
			$suma_posrednie_download += $posrednie_download{$nr};

			if ( $show > 2 ) {		
  				print "Posrednie download: $posrednie_download{$nr}\t Posrednie upload: $posrednie_upload{$nr}\n";
			}
		}
	}

	$wsp_pasm_upload   = $pasmo_max_upload   / ( $suma_posrednie_upload   + 1 );
	$wsp_pasm_download = $pasmo_max_download / ( $suma_posrednie_download + 1 );

	if ( $show > 2 ) {
		print "Wsp pasm download: $wsp_pasm_download \tWsp pasm upload: $wsp_pasm_upload\n";
		print "Suma posrednie download: $suma_posrednie_download \tSuma posrednie upload: $suma_posrednie_upload \n";
	}

	$a =0;	# TEMP
	$b =0;	# TEMP

	for ( $nr=0; $nr < $user_max; ++$nr )
	{
		if ( $activ{$nr} )
		{
			$pasmo_upload{$nr}   = $posrednie_upload{$nr}   * $wsp_pasm_upload;
			$pasmo_download{$nr} = $posrednie_download{$nr} * $wsp_pasm_download;

#			if ( $nr != 0 ) {
#				$pasmo_upload{$nr} = 10;
#				$pasmo_download{$nr} = 10;
#			}                

			$a += $pasmo_download{$nr};
			$b += $pasmo_upload{$nr};

			if ( $show > 1 ) {
  				print "\nHost: $lista_komp[$nr]\tPasmo download: $pasmo_download{$nr}   \tPasmo upload: $pasmo_upload{$nr}";
			}
		}
	}

	if ( $show > 1 ) {
  		print "\n\nLaczne pasmo download: $a \tLaczne pasmo upload: $b \n";
	}

  #========================================================================================
  #											 
  #   Aktualizacja kolejek TBF   
  #											 
  #========================================================================================



	for ( $nr=0; $nr < $user_max; ++$nr )
  	{
#		print "$nr:$pasmo_upload{$nr}_$pasmo_download{$nr}   ";


        $handle_up    = $nr + $start_ip;
		$handle_down  = $nr + $start_ip + 300;

        $classid_up   = $nr + $start_ip + 600;
		$classid_down = $nr + $start_ip + 900;


#		$pasmo_download{0} = 666000;
#		$pasmo_upload{0} = 111000;

#		print "IP:$nr  up: $pasmo_upload{$nr}  - ";

        system ("tc qdisc change dev ".$if_up." parent 1:".$classid_up." handle ".$classid_up.": tbf rate ".$pasmo_upload{$nr}."kbps burst ".$tbf_burst_up."b limit 32768 mpu 64");

#       system ("tc qdisc change dev ".$if_up." parent 1:".$classid_up." handle ".$classid_up.": tbf rate ".$pasmo_upload{$nr}."kbps latency ".$tbf_latency_up."ms burst ".$tbf_burst_up."b");
	
		if ( $traffic_down ) {

#			print "down: $pasmo_download{$nr}  -";
        	system ("tc qdisc change dev ".$if_down." parent 1:".$classid_down." handle ".$classid_down.": tbf rate ".$pasmo_download{$nr}."kbps burst ".$tbf_burst_down."b limit 128000 mpu 64");

#			system ("tc qdisc change dev ".$if_down." parent 1:".$classid_down." handle ".$classid_down.": tbf rate ".$pasmo_download{$nr}."kbps latency ".$tbf_latency_down."ms burst ".$tbf_burst_down."b");
# 			print " __________  ";
		}
	}


  ########################################################################################
  #        Zapis danych do plików 							 #
  ########################################################################################


#  # Odczytanie danych z poprzedniego wykonania skryptu
#  if( open(LOGFILE, $file) )
#  {
#          my(@lines) = <LOGFILE>;
#          close(LOGFILE);
#          foreach my $line (@lines)
#          {
#                  chomp($line);
#                  print $line."\n";
#                  {
#                          chomp $line;
#                          my ($host, $up, $down, $activ) = split(/\t+/, $line);
#                          $activity{$host} = $activity{$host} || $activ;
#                          $download{$host} = $download{$host} + $down;
#                          $upload{$host} = $upload{$host} + $up;
#                  }
#          }
#  }


  # zapis danych
#  open(OUTFILE, ">$file") or die("Fatal error: Unable to write '$file'. Exiting.\n");
#
#  for ($nr=0; $nr<50 ; ++$nr )
#  {
#         if($activ{$nr} ) {
#         $sum_up=$sum_up+$up{$nr};
#         $sum_down=$sum_down+$down{$nr};
#         print " Host: ".$lista_komp[$nr]."  Download: ".$down{$nr}."    Upload: ".$up{$nr};
#         print "\n";
#         };
# 
#  }
#  print "\n\n   Suma Download: ".$sum_down/$cykl."   Upload: ".$sum_up/$cykl."\n";
#
#  $all_up = $all_up + $sum_up;
#  $all_down = $all_down + $sum_down;
#
#  $a = $all_down/1024/1024;
#  $b = $all_up/1024/1024;
#  print "\n  Suma calkowita:   Download: $a MB    Upload: $b MB\n";
#
#  foreach my $host (keys %upload)
#  {
#      print OUTFILE "$host\t$upload{$host}\t$download{$host}\t$activity{$host}\n";
#  }
#  close(OUTFILE);
#
#
#
#



}

