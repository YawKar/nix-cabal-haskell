module Main (main) where

import Lib1 (greet)
import System.Environment (getArgs)

main :: IO ()
main = do
    args <- getArgs
    putStrLn $ greet $ case args of
        name : _ -> name
        [] -> "cli1"
