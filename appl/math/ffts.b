implement FFTs;
include "sys.m";
	sys: Sys;
	print: import sys;
include "math.m";
	math: Math;
	cos, sin, Degree, Pi: import math;
include "ffts.m";

#  by r. c. singleton, stanford research institute, sept. 1968
#  translated to limbo by eric grosse, jan 1997
#  arrays at(maxf), ck(maxf), bt(maxf), sk(maxf), and np(maxp)
#    are used for temporary storage.  if the available storage
#    is insufficient, the program exits.
#    maxf must be >= the maximum prime factor of n.
#    maxp must be > the number of prime factors of n.
#    in addition, if the square-free portion k of n has two or
#    more prime factors, then maxp must be >= k-1.
#  array storage in nfac for a maximum of 15 prime factors of n.
#  if n has more than one square-free factor, the product of the
#    square-free factors must be <= 210

ffts(a,b:array of real, ntot,n,nspan,isn:int){
	maxp: con 209;
	i,ii,inc,j,jc,jf,jj,k,k1,k2,k3,k4,kk:int;
	ks,kspan,kspnn,kt,m,maxf,nn,nt:int;
	aa,aj,ajm,ajp,ak,akm,akp,bb,bj,bjm,bjp,bk,bkm,bkp:real;
	c1,c2,c3,c72,cd,rad,radf,s1,s2,s3,s72,s120,sd:real;
	maxf = 23;
	if(math == nil){
		sys = load Sys Sys->PATH;
		math = load Math Math->PATH;
	}
	nfac := array[12] of int;
	np := array[maxp] of int;
	at := array[23] of real;
	ck := array[23] of real;
	bt := array[23] of real;
	sk := array[23] of real;

	if(n<2) return;
	inc = isn;
	c72 = cos(72.*Degree);
	s72 = sin(72.*Degree);
	s120 = sin(120.*Degree);
	rad = 2.*Pi;
	if(isn<0){
		s72 = -s72;
		s120 = -s120;
		rad = -rad;
		inc = -inc;
	}
	nt = inc*ntot;
	ks = inc*nspan;
	kspan = ks;
	nn = nt-inc;
	jc = ks/n;
	radf = rad*real(jc)*0.5;
	i = 0;
	jf = 0;

	#  determine the factors of n
	m = 0;
	k = n;
	while(k==k/16*16){
		m = m+1;
		nfac[m] = 4;
		k = k/16;
	}
	j = 3;
	jj = 9;
	for(;;)
		if(k%jj==0){
			m = m+1;
			nfac[m] = j;
			k = k/jj;
		}else{
			j = j+2;
			jj = j*j;
			if(jj>k)
				break;
		}
	if(k<=4){
		kt = m;
		nfac[m+1] = k;
		if(k!=1)
			m = m+1;
	}else{
		if(k==k/4*4){
			m = m+1;
			nfac[m] = 2;
			k = k/4;
		}
		kt = m;
		j = 2;
		do{
			if(k%j==0){
				m = m+1;
				nfac[m] = j;
				k = k/j;
			}
			j = ((j+1)/2)*2+1;
		}while(j<=k);
	}
	if(kt!=0){
		j = kt;
		do{
			m = m+1;
			nfac[m] = nfac[j];
			j = j-1;
		}while(j!=0);
	}

	for(;;){ #  compute fourier transform
		sd = radf/real(kspan);
		cd = sin(sd);
		cd = 2.0*cd*cd;
		sd = sin(sd+sd);
		kk = 1;
		i = i+1;
		if(nfac[i]==2){ #  transform for factor of 2 (including rotation factor)
			kspan = kspan/2;
			k1 = kspan+2;
			for(;;){
				k2 = kk+kspan;
				ak = a[k2-1];
				bk = b[k2-1];
				a[k2-1] = a[kk-1]-ak;
				b[k2-1] = b[kk-1]-bk;
				a[kk-1] = a[kk-1]+ak;
				b[kk-1] = b[kk-1]+bk;
				kk = k2+kspan;
				if(kk>nn){
					kk = kk-nn;
					if(kk>jc)
						break;
				}
			}
			if(kk>kspan)
				break;
			do{
				c1 = 1.0-cd;
				s1 = sd;
				for(;;){
					k2 = kk+kspan;
					ak = a[kk-1]-a[k2-1];
					bk = b[kk-1]-b[k2-1];
					a[kk-1] = a[kk-1]+a[k2-1];
					b[kk-1] = b[kk-1]+b[k2-1];
					a[k2-1] = c1*ak-s1*bk;
					b[k2-1] = s1*ak+c1*bk;
					kk = k2+kspan;
					if(kk>=nt){
						k2 = kk-nt;
						c1 = -c1;
						kk = k1-k2;
						if(kk<=k2){
							ak = c1-(cd*c1+sd*s1);
							s1 = (sd*c1-cd*s1)+s1;
							c1 = 2.0-(ak*ak+s1*s1);
							s1 = c1*s1;
							c1 = c1*ak;
							kk = kk+jc;
							if(kk>=k2)
								break;
						}
					}
				}
				k1 = k1+inc+inc;
				kk = (k1-kspan)/2+jc;
			}while(kk<=jc+jc);
		}else{	#  transform for factor of 4
			if(nfac[i]!=4){
				#  transform for odd factors
				k = nfac[i];
				kspnn = kspan;
				kspan = kspan/k;
				if(k==3)
					for(;;){
						#  transform for factor of 3 (optional code)
						k1 = kk+kspan;
						k2 = k1+kspan;
						ak = a[kk-1];
						bk = b[kk-1];
						aj = a[k1-1]+a[k2-1];
						bj = b[k1-1]+b[k2-1];
						a[kk-1] = ak+aj;
						b[kk-1] = bk+bj;
						ak = -0.5*aj+ak;
						bk = -0.5*bj+bk;
						aj = (a[k1-1]-a[k2-1])*s120;
						bj = (b[k1-1]-b[k2-1])*s120;
						a[k1-1] = ak-bj;
						b[k1-1] = bk+aj;
						a[k2-1] = ak+bj;
						b[k2-1] = bk-aj;
						kk = k2+kspan;
						if(kk>=nn){
							kk = kk-nn;
							if(kk>kspan)
								break;
						}
					}
				else if(k==5){
					#  transform for factor of 5 (optional code)
					c2 = c72*c72-s72*s72;
					s2 = 2.0*c72*s72;
					for(;;){
						k1 = kk+kspan;
						k2 = k1+kspan;
						k3 = k2+kspan;
						k4 = k3+kspan;
						akp = a[k1-1]+a[k4-1];
						akm = a[k1-1]-a[k4-1];
						bkp = b[k1-1]+b[k4-1];
						bkm = b[k1-1]-b[k4-1];
						ajp = a[k2-1]+a[k3-1];
						ajm = a[k2-1]-a[k3-1];
						bjp = b[k2-1]+b[k3-1];
						bjm = b[k2-1]-b[k3-1];
						aa = a[kk-1];
						bb = b[kk-1];
						a[kk-1] = aa+akp+ajp;
						b[kk-1] = bb+bkp+bjp;
						ak = akp*c72+ajp*c2+aa;
						bk = bkp*c72+bjp*c2+bb;
						aj = akm*s72+ajm*s2;
						bj = bkm*s72+bjm*s2;
						a[k1-1] = ak-bj;
						a[k4-1] = ak+bj;
						b[k1-1] = bk+aj;
						b[k4-1] = bk-aj;
						ak = akp*c2+ajp*c72+aa;
						bk = bkp*c2+bjp*c72+bb;
						aj = akm*s2-ajm*s72;
						bj = bkm*s2-bjm*s72;
						a[k2-1] = ak-bj;
						a[k3-1] = ak+bj;
						b[k2-1] = bk+aj;
						b[k3-1] = bk-aj;
						kk = k4+kspan;
						if(kk>=nn){
							kk = kk-nn;
							if(kk>kspan)
								break;
						}
					}
				}else{
					if(k!=jf){
						jf = k;
						s1 = rad/real(k);
						c1 = cos(s1);
						s1 = sin(s1);
						if(jf>maxf){
							sys->fprint(sys->fildes(2),"too many primes for fft");
							exit;
						}
						ck[jf-1] = 1.0;
						sk[jf-1] = 0.0;
						j = 1;
						do{
							ck[j-1] = ck[k-1]*c1+sk[k-1]*s1;
							sk[j-1] = ck[k-1]*s1-sk[k-1]*c1;
							k = k-1;
							ck[k-1] = ck[j-1];
							sk[k-1] = -sk[j-1];
							j = j+1;
						}while(j<k);
					}
					for(;;){
						k1 = kk;
						k2 = kk+kspnn;
						aa = a[kk-1];
						bb = b[kk-1];
						ak = aa;
						bk = bb;
						j = 1;
						k1 = k1+kspan;
						do{
							k2 = k2-kspan;
							j = j+1;
							at[j-1] = a[k1-1]+a[k2-1];
							ak = at[j-1]+ak;
							bt[j-1] = b[k1-1]+b[k2-1];
							bk = bt[j-1]+bk;
							j = j+1;
							at[j-1] = a[k1-1]-a[k2-1];
							bt[j-1] = b[k1-1]-b[k2-1];
							k1 = k1+kspan;
						}while(k1<k2);
						a[kk-1] = ak;
						b[kk-1] = bk;
						k1 = kk;
						k2 = kk+kspnn;
						j = 1;
						do{
							k1 = k1+kspan;
							k2 = k2-kspan;
							jj = j;
							ak = aa;
							bk = bb;
							aj = 0.0;
							bj = 0.0;
							k = 1;
							do{
								k = k+1;
								ak = at[k-1]*ck[jj-1]+ak;
								bk = bt[k-1]*ck[jj-1]+bk;
								k = k+1;
								aj = at[k-1]*sk[jj-1]+aj;
								bj = bt[k-1]*sk[jj-1]+bj;
								jj = jj+j;
								if(jj>jf)
									jj = jj-jf;
							}while(k<jf);
							k = jf-j;
							a[k1-1] = ak-bj;
							b[k1-1] = bk+aj;
							a[k2-1] = ak+bj;
							b[k2-1] = bk-aj;
							j = j+1;
						}while(j<k);
						kk = kk+kspnn;
						if(kk>nn){
							kk = kk-nn;
							if(kk>kspan)
								break;
						}
					}
				}
				#  multiply by rotation factor (except for factors of 2 and 4)
				if(i==m)
					break;
				kk = jc+1;
				do{
					c2 = 1.0-cd;
					s1 = sd;
					do{
						c1 = c2;
						s2 = s1;
						kk = kk+kspan;
						for(;;){
							ak = a[kk-1];
							a[kk-1] = c2*ak-s2*b[kk-1];
							b[kk-1] = s2*ak+c2*b[kk-1];
							kk = kk+kspnn;
							if(kk>nt){
								ak = s1*s2;
								s2 = s1*c2+c1*s2;
								c2 = c1*c2-ak;
								kk = kk-nt+kspan;
								if(kk>kspnn)
									break;
							}
						}
						c2 = c1-(cd*c1+sd*s1);
						s1 = s1+(sd*c1-cd*s1);
						c1 = 2.0-(c2*c2+s1*s1);
						s1 = c1*s1;
						c2 = c1*c2;
						kk = kk-kspnn+jc;
					}while(kk<=kspan);
					kk = kk-kspan+jc+inc;
				}while(kk<=jc+jc);
			}else{
				kspnn = kspan;
				kspan = kspan/4;
				do{
					c1 = 1.;
					s1 = 0.;
					for(;;){
						k1 = kk+kspan;
						k2 = k1+kspan;
						k3 = k2+kspan;
						akp = a[kk-1]+a[k2-1];
						akm = a[kk-1]-a[k2-1];
						ajp = a[k1-1]+a[k3-1];
						ajm = a[k1-1]-a[k3-1];
						a[kk-1] = akp+ajp;
						ajp = akp-ajp;
						bkp = b[kk-1]+b[k2-1];
						bkm = b[kk-1]-b[k2-1];
						bjp = b[k1-1]+b[k3-1];
						bjm = b[k1-1]-b[k3-1];
						b[kk-1] = bkp+bjp;
						bjp = bkp-bjp;
						do10 := 0;
						if(isn<0){
							akp = akm+bjm;
							akm = akm-bjm;
							bkp = bkm-ajm;
							bkm = bkm+ajm;
							if(s1!=0.) do10 = 1;
						}else{
							akp = akm-bjm;
							akm = akm+bjm;
							bkp = bkm+ajm;
							bkm = bkm-ajm;
							if(s1!=0.) do10 = 1;
						}
						if(do10){
							a[k1-1] = akp*c1-bkp*s1;
							b[k1-1] = akp*s1+bkp*c1;
							a[k2-1] = ajp*c2-bjp*s2;
							b[k2-1] = ajp*s2+bjp*c2;
							a[k3-1] = akm*c3-bkm*s3;
							b[k3-1] = akm*s3+bkm*c3;
							kk = k3+kspan;
							if(kk<=nt)
								continue;
						}else{
							a[k1-1] = akp;
							b[k1-1] = bkp;
							a[k2-1] = ajp;
							b[k2-1] = bjp;
							a[k3-1] = akm;
							b[k3-1] = bkm;
							kk = k3+kspan;
							if(kk<=nt)
								continue;
						}
						c2 = c1-(cd*c1+sd*s1);
						s1 = (sd*c1-cd*s1)+s1;
						c1 = 2.0-(c2*c2+s1*s1);
						s1 = c1*s1;
						c1 = c1*c2;
						c2 = c1*c1-s1*s1;
						s2 = 2.0*c1*s1;
						c3 = c2*c1-s2*s1;
						s3 = c2*s1+s2*c1;
						kk = kk-nt+jc;
						if(kk>kspan)
							break;
					}
					kk = kk-kspan+inc;
				}while(kk<=jc);
				if(kspan==jc)
					break;
			}
		}
	} # end "compute fourier transform"

	#  permute the results to normal order---done in two stages
	#  permutation for square factors of n
	np[0] = ks;
	if(kt!=0){
		k = kt+kt+1;
		if(m<k)
			k = k-1;
		j = 1;
		np[k] = jc;
		do{
			np[j] = np[j-1]/nfac[j];
			np[k-1] = np[k]*nfac[j];
			j = j+1;
			k = k-1;
		}while(j<k);
		k3 = np[k];
		kspan = np[1];
		kk = jc+1;
		k2 = kspan+1;
		j = 1;
		if(n!=ntot){
			for(;;){
				#  permutation for multivariate transform
				k = kk+jc;
				do{
					ak = a[kk-1];
					a[kk-1] = a[k2-1];
					a[k2-1] = ak;
					bk = b[kk-1];
					b[kk-1] = b[k2-1];
					b[k2-1] = bk;
					kk = kk+inc;
					k2 = k2+inc;
				}while(kk<k);
				kk = kk+ks-jc;
				k2 = k2+ks-jc;
				if(kk>=nt){
					k2 = k2-nt+kspan;
					kk = kk-nt+jc;
					if(k2>=ks)
	permm:					for(;;){
							k2 = k2-np[j-1];
							j = j+1;
							k2 = np[j]+k2;
							if(k2<=np[j-1]){
								j = 1;
								do{
									if(kk<k2)
										break permm;
									kk = kk+jc;
									k2 = kspan+k2;
								}while(k2<ks);
								if(kk>=ks)
									break permm;
							}
						}
				}
			}
			jc = k3;
		}else{
			for(;;){
				#  permutation for single-variate transform (optional code)
				ak = a[kk-1];
				a[kk-1] = a[k2-1];
				a[k2-1] = ak;
				bk = b[kk-1];
				b[kk-1] = b[k2-1];
				b[k2-1] = bk;
				kk = kk+inc;
				k2 = kspan+k2;
				if(k2>=ks)
	perms:				for(;;){
						k2 = k2-np[j-1];
						j = j+1;
						k2 = np[j]+k2;
						if(k2<=np[j-1]){
							j = 1;
							do{
								if(kk<k2)
									break perms;
								kk = kk+inc;
								k2 = kspan+k2;
							}while(k2<ks);
							if(kk>=ks)
								break perms;
						}
					}
			}
			jc = k3;
		}
	}
	if(2*kt+1>=m)
		return;
	kspnn = np[kt];
	#  permutation for square-free factors of n
	j = m-kt;
	nfac[j+1] = 1;
	do{
		nfac[j] = nfac[j]*nfac[j+1];
		j = j-1;
	}while(j!=kt);
	kt = kt+1;
	nn = nfac[kt]-1;
	if(nn<=maxp){
		jj = 0;
		j = 0;
		for(;;){
			k2 = nfac[kt];
			k = kt+1;
			kk = nfac[k];
			j = j+1;
			if(j>nn)
				break;
			for(;;){
				jj = kk+jj;
				if(jj<k2)
					break;
				jj = jj-k2;
				k2 = kk;
				k = k+1;
				kk = nfac[k];
			}
			np[j-1] = jj;
		}
		#  determine the permutation cycles of length greater than 1
		j = 0;
		for(;;){
			j = j+1;
			kk = np[j-1];
			if(kk>=0)
				if(kk==j){
					np[j-1] = -j;
					if(j==nn)
						break;
				}else{
					do{
						k = kk;
						kk = np[k-1];
						np[k-1] = -kk;
					}while(kk!=j);
					k3 = kk;
				}
		}
		maxf = inc*maxf;
		for(;;){
			j = k3+1;
			nt = nt-kspnn;
			ii = nt-inc+1;
			if(nt<0)
				break;
			for(;;){
				j = j-1;
				if(np[j-1]>=0){
					jj = jc;
					do{
						kspan = jj;
						if(jj>maxf)
							kspan = maxf;
						jj = jj-kspan;
						k = np[j-1];
						kk = jc*k+ii+jj;
						k1 = kk+kspan;
						k2 = 0;
						do{
							k2 = k2+1;
							at[k2-1] = a[k1-1];
							bt[k2-1] = b[k1-1];
							k1 = k1-inc;
						}while(k1!=kk);
						do{
							k1 = kk+kspan;
							k2 = k1-jc*(k+np[k-1]);
							k = -np[k-1];
							do{
								a[k1-1] = a[k2-1];
								b[k1-1] = b[k2-1];
								k1 = k1-inc;
								k2 = k2-inc;
							}while(k1!=kk);
							kk = k2;
						}while(k!=j);
						k1 = kk+kspan;
						k2 = 0;
						do{
							k2 = k2+1;
							a[k1-1] = at[k2-1];
							b[k1-1] = bt[k2-1];
							k1 = k1-inc;
						}while(k1!=kk);
					}while(jj!=0);
					if(j==1)
						break;
				}
			}
		}
	}
}
