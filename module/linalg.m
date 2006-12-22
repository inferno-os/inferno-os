# The convention used here for storing matrices is the same commonly
# used for scientific programming in C, namely linearizing in Fortran order.
# Let A be an m by n matrix.  We represent this by
#	a: array of real;
#	m, n, lda: int;
# where the variable lda ("leading dimension of a") is used so that a
# succession of matrix problems of varying sizes can be created without
# wholesale copying of data.  The element of A in the i-th row and j-th column
# is stored in a[i+lda*j], where 0<=i<m and 0<=j<n.  This 0-origin indexing
# is used everywhere, and in particular in permutation vectors.

LinAlg: module{
	PATH:	con "/dis/math/linalg.dis";

	Vector: type array of real;
	Matrix: adt{
		m, L, n: int;     # rows, column stride, columns
		a: Vector; # data, stored A[i,j] = a[i+L*j]
	};

	dgefa:	fn(a:array of real, lda, n:int, ipvt:array of int): int;
	dgesl:	fn(a:array of real, lda, n:int, ipvt:array of int, b:array of real, job:int);
	printmat: fn(label:string, a:array of real, lda, m, n:int);
};
