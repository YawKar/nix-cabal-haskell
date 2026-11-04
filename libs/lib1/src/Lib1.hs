-- | Greetings.
module Lib1 (greet, Person (Person), withName) where

import GHC.Generics qualified (Generic)
import Optics.Core ((&), (.~))

-- | Build a greeting for the given name.
--
-- >>> greet "world"
-- "Hello, world!"
greet :: String -> String
greet name = "Hello, " <> name <> "!"

data Person = Person
    { name :: String
    , age :: Int
    }
    deriving stock (Show, Eq, GHC.Generics.Generic)

-- | Update only the name of the person.
--
-- It's here just to use optics-core.
-- >>> Person "Yan" 23 `withName` "Yana"
-- Person {name = "Yana", age = 23}
withName :: Person -> String -> Person
withName p n = p & #name .~ n
