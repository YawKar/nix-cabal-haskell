module Main (main) where

import Lib1 qualified (greet)
import Lib2 qualified (shout)

main :: IO ()
main = do
    putStrLn (Lib1.greet "cli2")
    putStrLn (Lib2.shout "cli2")
