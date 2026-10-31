module Main (main) where

import Lib1 (greet)
import Test.Tasty.Bench

main :: IO ()
main =
    defaultMain
        [ bgroup
            "greet"
            [ bench "short name" $ nf greet "world"
            , bench "long name" $ nf greet (replicate 10000 'x')
            ]
        ]
