module Main (main) where

import Lib1 (greet)
import Test.Hspec

main :: IO ()
main = hspec $ do
    describe "greet" $ do
        it "greets by name" $
            greet "world" `shouldBe` "Hello, world!"
