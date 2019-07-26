(* ::Package:: *)

BeginPackage["Sledgehammer`"];

Begin["`Private`"];


(* ::Subsection:: *)
(*Literal encodings*)


(* ::Subsubsection::Closed:: *)
(*Integers (Elias gamma, delta)*)


eliasGamma[0] := {1}
eliasGamma[n_Integer /; n > 0] := IntegerDigits[n,2] // Join[ConstantArray[0,Length@# - 1], #]&;

eliasDelta[n_Integer /; n > 0] := IntegerDigits[n,2] // Join[eliasGamma[Length@#], Rest@# ]&;

eliasDelta[_] := Throw@"Argument to Elias Delta must be a positive integer."

(* Elias delta except for the lower k bits which are explicitly encoded, and the sign which is the first bit if sgnQ = True. *)
varEliasDelta[n_Integer, k_Integer: 1, sgnQ_: True] := Module[{nn, sgn, ret},
	If[!sgnQ, Assert[n >= 0]];
	sgn = Boole[n < 0];
	nn = BitXor[n, -sgn]; (* BitNot[n] if n < 0 else n *)
	ret = Join[eliasDelta[Floor[nn/2^k]+1], IntegerDigits[nn,2,k]];
	If[sgnQ, Join[{sgn},ret], ret]
];

(* returns n, length used *)
unEliasGamma[bits_List] := Module[{leadingZeros = Count[First@Split@bits,0]},
	{FromDigits[bits[[leadingZeros + 1;; 2 leadingZeros + 1]],2],
	2 leadingZeros + 1}
];

(* returns n, length used *)
unEliasDelta[bits_List] := Module[{lennp1, lenUsed},
	{lennp1, lenUsed} = unEliasGamma[bits];
	{FromDigits[ Prepend[1]@ bits[[lenUsed + 1 ;; lenUsed + lennp1 - 1]], 2], lenUsed + lennp1 - 1}
];

(* returns integer, length used
To do: Change integer literals to k=1 *)
unVarEliasDelta::usage = "Decode a variant Elias Delta bitstring";
unVarEliasDelta[bits_List, k_Integer:1, sgnQ_:True] := Module[{sgn, rest, ndiv8p1, lenUsed, n},
	sgn = If[sgnQ, First@bits,0];
	rest = If[sgnQ,Rest@bits, bits];
	{ndiv8p1, lenUsed} = unEliasDelta[rest];
	n = (ndiv8p1 - 1) * 2^k + FromDigits[ rest[[lenUsed+1 ;; lenUsed+k]], 2];
	n = BitXor[n,-sgn];
	(* bits used = Elias Delta bits + low bits + sign bit *)
	{n, lenUsed + k + Boole@sgnQ}
];
(* modified Elias Delta, mod 2^3 *)
tokenToBits[intLiteral[n_Integer]] := Join[tokenToBits@intLiteral[], varEliasDelta[n, 1, True]];


(* ::Subsubsection:: *)
(*Reals*)


(* convert real numbers to digit lists *)
tokenToBits[realLiteral[x_Real]] := Module[{str, len, bits},
	str = ToString[x, InputForm];
	bits = fromBijectiveBase[(ToCharacterCode@str /. 10 -> 127) - 31, 96]~IntegerDigits~2;
	len = Length@bits;
	Join[tokenToBits@realLiteral[], varEliasDelta[len, 3, False], bits]
];



(* ::Subsubsection::Closed:: *)
(*Bijective base*)


(* convert n to bijective base k *)
toBijectiveBase[n_Integer, k_Integer] := Module[{acc = n, ret = {}, digit},
	While[acc > 0,
		digit = Mod[acc-1, k] + 1;
		PrependTo[ret, digit];
		acc = Quotient[acc-1, k]];
	ret
];

fromBijectiveBase[l_List, k_Integer] := FromDigits[l, k];


(* ::Subsubsection::Closed:: *)
(*Strings*)


(* ASCII strings packed into 7 bits per character.*)
tokenToBits[asciiLiteral[str_String] /; SubsetQ[Union[{10}, Range[32, 127]], Union@ToCharacterCode@str] ] := encodeAsciiLiteral[str];
tokenToBits[asciiLiteral[str_]] := tokenToBits[asciiLiteral[""]];

encodeAsciiLiteral[str_String] := Module[{len, bits},
	bits = fromBijectiveBase[(ToCharacterCode@str /. 10 -> 127) - 31, 96]// IntegerDigits[#,2]&;
	len = Length@bits;
	Join[tokenToBits@asciiLiteral[], varEliasDelta[len, 3, False], bits]
];

(* ASCII literal. (Length of string, string in packed 7 bit encoding) *)
decodeAsciiLiteral[bits_] := Module[{len, lenLen},
	{len, lenLen} = unVarEliasDelta[bits, 3, False];
	Drop[bits, lenLen] //
	Take[#, len]& //
	toBijectiveBase[FromDigits[#, 2], 96]& //
	(# + 31 /. 127 -> 10&) //
	FromCharacterCode //
	{#, lenLen + len } &
];


(* ::Subsection:: *)
(*Data encoders*)


(* ::Subsubsection:: *)
(*Bit model*)


$bitModel = <| 0 -> .5, 1 -> .5 |>&;

encodeBit[bit: 0 | 1] := Module[{},
	encodeToken[bit, $bitModel]
];

encodeBits[bits: {Integer___}] := Scan[encodeBit, bits];

decodeBit[] := Module[{},
	decodeToken[$bitModel]
];

decodeBits[n_Integer] := Table[decodeBit[], n];


(* ::Subsubsection:: *)
(*Integer literals*)


(* pulls from stream *)
unEliasGamma[] := Module[{leadingZeros = 0, ret},
	 While[decodeBit[] == 0, ++leadingZeros; If[leadingZeros > 100, Throw["Too many leading 0s!"]] ];
	 (* bit we just read is a 1 *)
	 show["leading zeros:"@leadingZeros];
	ret = FromDigits[Prepend[decodeBits[leadingZeros], 1],2];
	show["unEliasGamma="@ret];
	ret
];

(* returns n, length used *)
unEliasDelta[] := Module[{lennp1, ret},
	lennp1 = unEliasGamma[];
	Assert[lennp1 >= 1];
	ret = FromDigits[ Prepend[1]@ decodeBits[lennp1 - 1], 2];
	show["unEliasDelta="@ret];
	ret
];

unVarEliasDelta[k_Integer:1, sgnQ_:True] := Module[{sgn, rest, ndiv8p1, ret},
	sgn = If[sgnQ, decodeBit[], 0];
	ndiv8p1 = unEliasDelta[];
	ret = (ndiv8p1 - 1) * 2^k + FromDigits[ show@decodeBits[k], 2];
	ret = BitXor[ret, -sgn];
	show["unVarEliasDelta="@ret];
	ret
];

encIntLiteral[data_Integer] := varEliasDelta[data] // encodeBits;

decIntLiteral[] := unVarEliasDelta[]


(* ::Subsubsection::Closed:: *)
(*String literals*)


encStrLiteral[str_String] := Module[{len, bits},
	bits = fromBijectiveBase[(ToCharacterCode@str /. 10 -> 127) - 31, 96]// IntegerDigits[#,2]&;
	len = Length@bits;
	Join[varEliasDelta[len, 3, False], bits] // encodeBits;
];

decStrLiteral=.
decStrLiteral[] := Module[{len, bits},
	(*decodeBits[8] // FromDigits[#, 2]& // FromCharacterCode*)
	len = unVarEliasDelta[3, False];
	bits = decodeBits[len];
	toBijectiveBase[FromDigits[bits, 2], 96] //
	(# + 31 /. 127 -> 10)& //
	FromCharacterCode
];


(* ::Subsubsection::Closed:: *)
(*Real literals*)


encRealLiteral[x_Real] := With[{str = ToString[x, InputForm]},
	encStrLiteral[str]
];

decRealLiteral=.
decRealLiteral[] := With[{str = decStrLiteral[]},
	ToExpression@str
]


(* ::Subsubsection:: *)
(*Novel tokens*)


(* requires list of names *)

$names = {"haskell", "julia", "ada"};

encNovelToken[tok_] := Module[{name, arity},
	{name, arity} = Switch[tok,
		_call, List@@tok,
		_symbolLiteral, {tok[[1]], -1},
		_, Throw["Invalid novel token"@tok]
	];
	encodeBits@Join[eliasGamma[arity + 2], varEliasDelta@First@FirstPosition[$names, name]];
]

decNovelToken[] := Module[{name, arity},
	arity = unEliasGamma[] - 2;
	name = $names[[unVarEliasDelta[]]];
	Switch[arity,
		-1, symbolLiteral[name],
		_, call[name, arity]]
];


(* ::Subsection:: *)
(*Models*)


ClearAll[tokenModel]

tokenModel[spf_SequencePredictorFunction, 0 | 0. ][l_List] := If[l==={}, First@spf[{{}}, "Probabilities"], spf[l, "Probabilities"]]

tokenModel[spf_SequencePredictorFunction, escapeProb_Real][l_List] :=
	Join[
		If[l==={}, First@spf[{{}}, "Probabilities"], spf[l, "Probabilities"]],
		<| novelToken[] -> escapeProb|>
	] / (1 + escapeProb);
tokenModel[spf_SequencePredictorFunction] := tokenModel[spf, .05]


(* ::Subsection:: *)
(**)


End[];
EndPackage[];