-- | Greetings.
module Lib1 (greet) where

-- | Build a greeting for the given name.
--
-- >>> greet "world"
-- "Hello, world!"
greet :: String -> String
greet name = "Hello, " <> name <> "!"
