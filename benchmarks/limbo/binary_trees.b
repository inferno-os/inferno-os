implement BenchBinaryTrees;

include "sys.m";
	sys: Sys;

include "draw.m";

BenchBinaryTrees: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

Node: adt {
	left: cyclic ref Node;
	right: cyclic ref Node;
};

makeTree(depth: int): ref Node
{
	if(depth == 0)
		return ref Node(nil, nil);
	return ref Node(makeTree(depth-1), makeTree(depth-1));
}

checkTree(node: ref Node): int
{
	if(node.left == nil)
		return 1;
	return 1 + checkTree(node.left) + checkTree(node.right);
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;

	t1 := sys->millisec();
	depth := 18;
	iterations := 5;
	total := 0;
	for(iter := 0; iter < iterations; iter++) {
		tree := makeTree(depth);
		total += checkTree(tree);
	}
	t2 := sys->millisec();
	sys->print("BENCH binary_trees %d ms %d iters %d\n", t2-t1, iterations, total);
}
