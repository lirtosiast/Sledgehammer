(* ::Package:: *)

BeginPackage["Sledgehammer`"];

Begin["`Private`"];
(* APL's monadic iota *)
IndexRange[dims_List] := Array[{##}&, dims];

(* APL's monadic iota-rho *)
Indices[arr_] := IndexRange@Dimensions@arr;

FlatIndices[arr_] := Flatten[Indices@arr, Range@ArrayDepth@arr]

(* Generalization of diagonals *)
ArrayBand[arr_, start_, end_, step_] := Module[{indices},
	Extract[arr, Table[ start + step x , {x, 0, Min[(end - start) / step]}]]
]

ArrayBand[arr_, start_, All, step_] := ArrayBand[arr, start, Dimensions@arr, step]

Bands[arr_, step_, starts_] := ArrayBand[arr, #, All, step]& /@ starts;

Bands[arr_, step_List ? VectorQ] := With[{
starts = Select[FlatIndices@arr, Min[# - step] <= 0 &] },
	Bands[arr, step, starts]
];

Bands[arr_, steps_List /; ! VectorQ[steps] && ArrayQ[steps] ] := Bands[arr]

LongestBands[arr_, step_List] := MaximalBy[Bands[arr, step], Length]

End[];
EndPackage[];
