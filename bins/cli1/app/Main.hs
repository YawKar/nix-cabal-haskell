module Main (main) where

import Lib1 qualified (greet)
import System.Environment qualified (getArgs)

main :: IO ()
main = do
    args <- System.Environment.getArgs
    putStrLn $ Lib1.greet $ case args of
        name : _ -> name
        [] -> "cli1"
