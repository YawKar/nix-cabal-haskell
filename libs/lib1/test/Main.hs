module Main (main) where

import Test.Hspec qualified as H

import Lib1 qualified (Person (Person), greet, withName)

main :: IO ()
main = H.hspec $ do
    H.describe "greet" $ do
        H.it "greets by name" $
            Lib1.greet "world" `H.shouldBe` "Hello, world!"

    H.describe "withName" $ do
        H.it "withName updates name" $
            (Lib1.Person "Yan" 23 `Lib1.withName` "Yana") `H.shouldBe` Lib1.Person "Yana" 23
