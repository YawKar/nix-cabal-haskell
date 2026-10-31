-- | Louder greetings, built on top of "Lib1".
module Lib2 (shout) where

import Data.Char (toUpper)
import Lib1 (greet)

-- | A louder 'greet'.
--
-- >>> shout "world"
-- "HELLO, WORLD!"
shout :: String -> String
shout = map toUpper . greet
