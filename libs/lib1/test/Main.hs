module Main (main) where

import Test.Hspec qualified as Hspec

import Lib1 qualified (greet)

main :: IO ()
main = Hspec.hspec $ do
    Hspec.describe "greet" $ do
        Hspec.it "greets by name" $
            Lib1.greet "world" `Hspec.shouldBe` "Hello, world!"
