-- | Louder greetings, built on top of "Lib1".
module Lib2 (shout) where

import Data.Char qualified (toUpper)
import Lib1 qualified (greet)

-- | A louder 'greet'.
--
-- >>> shout "world"
-- "HELLO, WORLD!"
shout :: String -> String
shout = map Data.Char.toUpper . Lib1.greet
