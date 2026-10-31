module Main (main) where

import Lib2 (shout)
import Test.Tasty.Bench

main :: IO ()
main =
    defaultMain
        [ bgroup
            "shout"
            [ bench "short name" $ nf shout "world"
            , bench "long name" $ nf shout (replicate 10000 'x')
            ]
        ]
