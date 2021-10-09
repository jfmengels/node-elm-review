module Elm.Review.Vendor.List.Extra exposing (gatherEqualsBy)

{-| Copied from <https://github.com/elm-community/list-extra>

The following is the original license

---

The MIT License (MIT)

Copyright (c) 2016 CircuitHub Inc., Elm Community members

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

-}


{-| Group equal elements together. A function is applied to each element of the list
and then the equality check is performed against the results of that function evaluation.
Elements will be grouped in the same order as they appear in the original list. The
same applies to elements within each group.
gatherEqualsBy .age [{age=25},{age=23},{age=25}]
--> [({age=25},[{age=25}]),({age=23},[])]
-}
gatherEqualsBy : (a -> b) -> List a -> List ( a, List a )
gatherEqualsBy extract list =
    gatherWith (\a b -> extract a == extract b) list


{-| Group equal elements together using a custom equality function. Elements will be
grouped in the same order as they appear in the original list. The same applies to
elements within each group.
gatherWith (==) [1,2,1,3,2]
--> [(1,[1]),(2,[2]),(3,[])]
-}
gatherWith : (a -> a -> Bool) -> List a -> List ( a, List a )
gatherWith testFn list =
    let
        helper : List a -> List ( a, List a ) -> List ( a, List a )
        helper scattered gathered =
            case scattered of
                [] ->
                    List.reverse gathered

                toGather :: population ->
                    let
                        ( gathering, remaining ) =
                            List.partition (testFn toGather) population
                    in
                    helper remaining (( toGather, gathering ) :: gathered)
    in
    helper list []
