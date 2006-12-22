implement CBPuzzle;

# Cracker Barrel Puzzle
#
# Holes are drilled in a triangular arrangement into which all but one
# are seated pegs. A 6th order puzzle appears in the diagram below.
# Note, the hole in the lower left corner of the triangle is empty.
#
#                 V
#               V   V
#             V   V   V
#           V   V   V   V
#         V   V   V   V   V
#       O   V   V   V   V   V
#
# Pegs are moved by jumping over a neighboring peg thereby removing the
# jumped peg. A peg can only be moved if a neighboring hole contains a
# peg and the hole on the other side of the neighbor is empty. The last
# peg cannot be removed.
#
# The object is to remove as many pegs as possible.

include "sys.m";
   sys: Sys;
include "draw.m";

CBPuzzle: module {
   init: fn(nil: ref Draw->Context, args: list of string);
};

ORDER: con 6;

Move: adt {
   x, y: int;
};

valid:= array[] of {Move (1,0), (0,1), (-1,1), (-1,0), (0,-1), (1,-1)};

board:= array[ORDER*ORDER] of int;
pegs, minpegs: int;

puzzle(): int
{
   if (pegs < minpegs)
      minpegs = pegs;

   if (pegs == 1)
      return 1;

   # Check each row of puzzle
   for (r := 0; r < ORDER; r += 1)
      # Check each column
      for (c := 0; c < ORDER-r; c += 1) {
         fromx := r*ORDER + c;
         # Is a peg in this hole?
         if (board[fromx])
            # Check valid moves from this hole
            for (m := 0; m < len valid; m += 1) {
               tor := r + 2*valid[m].y;
               toc := c + 2*valid[m].x;

               # Is new location still on the board?
               if (tor + toc < ORDER && tor >= 0 && toc >= 0) {
                  jumpr := r + valid[m].y;
                  jumpc := c + valid[m].x;
                  jumpx := jumpr*ORDER + jumpc;

                  # Is neighboring hole occupied?
                  if (board[jumpx]) {
                     # Is new location empty?
                     tox := tor*ORDER + toc;

                     if (! board[tox]) {
                        # Jump neighboring hole
                        board[fromx] = 0;
                        board[jumpx] = 0;
                        board[tox] = 1;
                        pegs -= 1;

                        # Try solving puzzle from here
                        if (puzzle()) {
                           #sys->print("(%d,%d) - (%d,%d)\n", r, c, tor, toc);
                           return 1;
                        }
                        # Dead end, put pegs back and try another move
                        board[fromx] = 1;
                        board[jumpx] = 1;
                        board[tox] = 0;
                        pegs += 1;
                     } # empty location
                  } # occupied neighbor
               } # still on board
            } # valid moves
      }
   return 0;
}

solve(): int
{
   minpegs = pegs = (ORDER+1)*ORDER/2 - 1;

   # Put pegs on board
   for (r := 0; r < ORDER; r += 1)
      for (c := 0; c < ORDER - r; c += 1)
         board[r*ORDER + c] = 1;

   # Remove one peg
   board[0] = 0;

   return puzzle();
}

init(nil: ref Draw->Context, args: list of string)
{
   sys = load Sys Sys->PATH;

   TRIALS: int;
   if (len args < 2)
      TRIALS = 1;
   else
      TRIALS = int hd tl args;

   start := sys->millisec();
   for (trials := 0; trials < TRIALS; trials += 1)
      solved := solve();
   end := sys->millisec();

   sys->print("%d ms\n", end - start);

   if (! solved)
      sys->print("No solution\n");
   sys->print("Minimum pegs: %d\n", minpegs);
}
