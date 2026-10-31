module Main (main) where

import Lib1 (greet)
import Lib2 (shout)

main :: IO ()
main = do
    putStrLn (greet "cli2")
    putStrLn (shout "cli2")
