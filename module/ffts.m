FFTs: module{
	PATH:	con	"/dis/math/ffts.dis";

	ffts: fn(a,b:array of real, ntot,n,nspan,isn:int);
};

#  multivariate complex fourier transform, computed in place
#    using mixed-radix fast fourier transform algorithm.
#  arrays a and b originally hold the real and imaginary
#    components of the data, and return the real and
#    imaginary components of the resulting fourier coefficients.
#  multivariate data is indexed according to the fortran
#    array element successor function, without limit
#    on the number of implied multiple subscripts.
#    the subroutine is called once for each variate.
#    the calls for a multivariate transform may be in any order.
#  ntot is the total number of complex data values.
#  n is the dimension of the current variable.
#  nspan/n is the spacing of consecutive data values
#    while indexing the current variable.
#  the sign of isn determines the sign of the complex
#    exponential, and the magnitude of isn is normally one.
#  univariate transform:
#      ffts(a,b,n,n,n,1)
#  trivariate transform with a(n1,n2,n3), b(n1,n2,n3):
#      ffts(a,b,n1*n2*n3,n1,n1,1)
#      ffts(a,b,n1*n2*n3,n2,n1*n2,1)
#      ffts(a,b,n1*n2*n3,n3,n1*n2*n3,1)
#  the data can alternatively be stored in a single vector c
#    alternating real and imaginary parts. the magnitude of isn changed
#    to two to give correct indexing increment, and a[0:] and a[1:] used
#    for a and b
