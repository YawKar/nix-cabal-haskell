module Main (main) where

import Test.Tasty.Bench qualified as B

import Lib2 qualified (shout)

main :: IO ()
main =
    B.defaultMain
        [ B.bgroup
            "shout"
            [ B.bench "short name" $ B.nf Lib2.shout "world"
            , B.bench "long name" $ B.nf Lib2.shout (replicate 10000 'x')
            ]
        ]
