module Main (main) where

import Test.Tasty.Bench qualified as B

import Lib1 qualified (greet)

main :: IO ()
main =
    B.defaultMain
        [ B.bgroup
            "greet"
            [ B.bench "short name" $ B.nf Lib1.greet "world"
            , B.bench "long name" $ B.nf Lib1.greet (replicate 10000 'x')
            ]
        ]
