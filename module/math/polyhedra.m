Polyhedra: module
{
	PATH: con "/dis/math/polyhedra.dis";

	Vector: adt{
		x, y, z: real;
	};

	Polyhedron: adt{
		name, dname: string;
		indx, V, E, F, concave, anti, allf, adj: int;
		v, f: array of Vector;
		fv, vf: array of array of int;
		offset: big;
		prv, nxt: cyclic ref Polyhedron;
		inc: real;
	};

	# read in details of all polyhedra in the given file
	scanpolyhedra: fn(f: string): (int, ref Polyhedron, ref Bufio->Iobuf);
	# read in the coordinates of all polyhedra
	getpolyhedra: fn(p: ref Polyhedron, b: ref Bufio->Iobuf);
	# read in the coordinates of the given polyhedron
	getpolyhedron: fn(p: ref Polyhedron, b: ref Bufio->Iobuf);
};
