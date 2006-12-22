implement LinAlg;

include "sys.m";
sys: Sys;
print: import sys;

include "math.m";
math: Math;
ceil, fabs, floor, Infinity, log10, pow10, sqrt: import math;
dot, gemm, iamax: import math;

include "linalg.m";

# print a matrix in MATLAB-compatible format
printmat(label:string, a:array of real, lda, m, n:int)
{
	if(m>30 || n>10)
		return;
	if(sys==nil){
		sys = load Sys Sys->PATH;
		math = load Math Math->PATH;
	}
	print("%% %d by %d matrix\n",m,n);
	print("%s = [",label);
	for(i:=0; i<m; i++){
		print("%.4g",a[i]);
		for(j:=1; j<n; j++)
			print(", %.4g",a[i+lda*j]);
		if(i==m-1)
			print("]\n");
		else
			print(";\n");
	}
}


# Constant times a vector plus a vector.
daxpy(da:real, dx:array of real, dy:array of real)
{
	n := len dx;
	gemm('N','N',n,1,n,da,nil,0,dx,n,1.,dy,n);
}

# Scales a vector by a constant.
dscal(da:real, dx:array of real)
{
	n := len dx;
	gemm('N','N',n,1,n,0.,nil,0,nil,0,da,dx,n);
}

# gaussian elimination with partial pivoting
#   dgefa factors a double precision matrix by gaussian elimination.
#   dgefa is usually called by dgeco, but it can be called
#   directly with a saving in time if  rcond  is not needed.
#   (time for dgeco) = (1 + 9/n)*(time for dgefa) .
#   on entry
#      a       REAL precision[n][lda]
#	      the matrix to be factored.
#      lda     integer
#	      the leading dimension of the array  a .
#      n       integer
#	      the order of the matrix  a .
#   on return
#      a       an upper triangular matrix and the multipliers
#	      which were used to obtain it.
#	      the factorization can be written  a = l*u  where
#	      l  is a product of permutation and unit lower
#	      triangular matrices and  u  is upper triangular.
#      ipvt    integer[n]
#	      an integer vector of pivot indices.
#      info    integer
#	      = 0  normal value.
#	      = k  if  u[k][k] .eq. 0.0 .  this is not an error
#		   condition for this subroutine, but it does
#		   indicate that dgesl or dgedi will divide by zero
#		   if called.  use  rcond  in dgeco for a reliable
#		   indication of singularity.
dgefa(a:array of real, lda, n:int, ipvt:array of int): int
{
	if(sys==nil){
		sys = load Sys Sys->PATH;
		math = load Math Math->PATH;
	}
	info := 0;
	nm1 := n - 1;
	if(nm1 >= 0)
	    for(k := 0; k < nm1; k++){
		kp1 := k + 1;
		ldak := lda*k;
	
		# find l = pivot index
		l := iamax(a[ldak+k:ldak+n]) + k;
		ipvt[k] = l;
	
		# zero pivot implies this column already triangularized
		if(a[ldak+l]!=0.){
	
		    # interchange if necessary
		    if(l!=k){
			t := a[ldak+l];
			a[ldak+l] = a[ldak+k];
			a[ldak+k] = t;
		    }
	
		    # compute multipliers
		    t := -1./a[ldak+k];
		    dscal(t,a[ldak+k+1:ldak+n]);
	
		    # row elimination with column indexing
		    for(j := kp1; j < n; j++){
			ldaj := lda*j;
			t = a[ldaj+l];
			if(l!=k){
			    a[ldaj+l] = a[ldaj+k];
			    a[ldaj+k] = t;
			}
			daxpy(t,a[ldak+k+1:ldak+n],a[ldaj+k+1:ldaj+n]);
		    }
		}else
		    info = k;
	    }
	ipvt[n-1] = n-1;
	if(a[lda*(n-1)+(n-1)] == 0.)
	    info = n-1;
	return info;
}


#   dgesl solves the double precision system
#   a * x = b  or  trans(a) * x = b
#   using the factors computed by dgeco or dgefa.
#   on entry
#      a       double precision[n][lda]
#	      the output from dgeco or dgefa.
#      lda     integer
#	      the leading dimension of the array  a .
#      n       integer
#	      the order of the matrix  a .
#      ipvt    integer[n]
#	      the pivot vector from dgeco or dgefa.
#      b       double precision[n]
#	      the right hand side vector.
#      job     integer
#	      = 0	 to solve  a*x = b ,
#	      = nonzero   to solve  trans(a)*x = b  where
#			  trans(a)  is the transpose.
#  on return
#      b       the solution vector  x .
#   error condition
#      a division by zero will occur if the input factor contains a
#      zero on the diagonal.  technically this indicates singularity
#      but it is often caused by improper arguments or improper
#      setting of lda.
dgesl(a:array of real, lda, n:int, ipvt:array of int, b:array of real, job:int)
{
	nm1 := n - 1;
	if(job == 0){	# job = 0 , solve  a * x = b
	    # first solve  l*y = b	
	    if(nm1 >= 1)
		for(k := 0; k < nm1; k++){
		    l := ipvt[k];
		    t := b[l];
		    if(l!=k){
			b[l] = b[k];
			b[k] = t;
		    }
		    daxpy(t,a[lda*k+k+1:lda*k+n],b[k+1:n]);
		}

	    # now solve  u*x = y
	    for(kb := 0; kb < n; kb++){
		k = n - (kb + 1);
		b[k] = b[k]/a[lda*k+k];
		t := -b[k];
		daxpy(t,a[lda*k:lda*k+k],b[0:k]);
	    }
	}else{	# job = nonzero, solve  trans(a) * x = b
	    # first solve  trans(u)*y = b	
	    for(k := 0; k < n; k++){
		t := dot(a[lda*k:lda*k+k],b[0:k]);
		b[k] = (b[k] - t)/a[lda*k+k];
	    }

	    # now solve trans(l)*x = y
	    if(nm1 >= 1)
		for(kb := 1; kb < nm1; kb++){
		    k = n - (kb+1);
		    b[k] += dot(a[lda*k+k+1:lda*k+n],b[k+1:n]);
		    l := ipvt[k];
		    if(l!=k){
			t := b[l];
			b[l] = b[k];
			b[k] = t;
		    }
		}
	 }
}
