#include "lib9.h"
#include "mathi.h"
void
gemm(int transa, int transb, int m, int n, int k, double alpha,
	double *a, int lda,
	double *b, int ldb, double beta,
	double *c, int ldc)
{
    int i1, i2, i3, nota, notb, i, j, jb, jc, l, la;
    double temp;

    nota = transa=='N';
    notb = transb=='N';

    if(m == 0 || n == 0 || (alpha == 0. || k == 0) && beta == 1.){
	return;
    }
    if(alpha == 0.){
	if(beta == 0.){
	    i1 = n;
	    for(j = 0; j < i1; ++j){
		jc = j*ldc;
		i2 = m;
		for(i = 0; i < i2; ++i){
		    c[i + jc] = 0.;
		}
	    }
	}else{
	    i1 = n;
	    for(j = 0; j < i1; ++j){
		jc = j*ldc;
		i2 = m;
		for(i = 0; i < i2; ++i){
		    c[i + jc] = beta * c[i + jc];
		}
	    }
	}
	return;
    }

    if(!a){
	if(notb){   /* C := alpha*B + beta*C. */
	    i1 = n;
	    for(j = 0; j < i1; ++j){
		jb = j*ldb;
		jc = j*ldc;
		i2 = m;
		for(i = 0; i < i2; ++i){
		    c[i + jc] = alpha*b[i+jb] + beta*c[i+jc];
		}
	    }
	}else{   /* C := alpha*B' + beta*C. */
	    i1 = n;
	    for(j = 0; j < i1; ++j){
		jc = j*ldc;
		i2 = m;
		for(i = 0; i < i2; ++i){
		    c[i + jc] = alpha*b[j+i*ldb] + beta*c[i+jc];
		}
	    }
	}
	return;
    }

    if(notb){
	if(nota){

/*          Form  C := alpha*A*B + beta*C. */
	    i1 = n;
	    for(j = 0; j < i1; ++j){
		jc = j*ldc;
		if(beta == 0.){
		    i2 = m;
		    for(i = 0; i < i2; ++i){
			c[i + jc] = 0.;
		    }
		}else if(beta != 1.){
		    i2 = m;
		    for(i = 0; i < i2; ++i){
			c[i + jc] = beta * c[i + jc];
		    }
		}
		i2 = k;
		for(l = 0; l < i2; ++l){
		    la = l*lda;
		    if(b[l + j*ldb] != 0.){
			temp = alpha * b[l + j*ldb];
			i3 = m;
			for(i = 0; i < i3; ++i){
			    c[i + jc] += temp * a[i + la];
			}
		    }
		}
	    }
	}else{

/*          Form  C := alpha*A'*B + beta*C */
	    i1 = n;
	    for(j = 0; j < i1; ++j){
		jc = j*ldc;
		i2 = m;
		for(i = 0; i < i2; ++i){
		    temp = 0.;
		    i3 = k;
		    for(l = 0; l < i3; ++l){
			temp += a[l + i*lda] * b[l + j*ldb];
		    }
		    if(beta == 0.){
			c[i + jc] = alpha * temp;
		    }else{
			c[i + jc] = alpha * temp + beta * c[i + jc];
		    }
		}
	    }
	}
    }else{
	if(nota){

/*          Form  C := alpha*A*B' + beta*C */
	    i1 = n;
	    for(j = 0; j < i1; ++j){
		jc = j*ldc;
		if(beta == 0.){
		    i2 = m;
		    for(i = 0; i < i2; ++i){
			c[i + jc] = 0.;
		    }
		}else if(beta != 1.){
		    i2 = m;
		    for(i = 0; i < i2; ++i){
			c[i + jc] = beta * c[i + jc];
		    }
		}
		i2 = k;
		for(l = 0; l < i2; ++l){
		    if(b[j + l*ldb] != 0.){
			temp = alpha * b[j + l*ldb];
			i3 = m;
			for(i = 0; i < i3; ++i){
			    c[i + jc] += temp * a[i + l*lda];
			}
		    }
		}
	    }
	}else{

/*          Form  C := alpha*A'*B' + beta*C */
	    i1 = n;
	    for(j = 0; j < i1; ++j){
		jc = j*ldc;
		i2 = m;
		for(i = 0; i < i2; ++i){
		    temp = 0.;
		    i3 = k;
		    for(l = 0; l < i3; ++l){
			temp += a[l + i*lda] * b[j + l*ldb];
		    }
		    if(beta == 0.){
			c[i + jc] = alpha * temp;
		    }else{
			c[i + jc] = alpha * temp + beta * c[i + jc];
		    }
		}
	    }
	}
    }
}
