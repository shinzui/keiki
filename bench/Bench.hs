module Main (main) where

import Test.Tasty.Bench (Benchmark, bench, bgroup, defaultMain, nf)

main :: IO ()
main = defaultMain benchmarks

benchmarks :: [Benchmark]
benchmarks =
  [ bgroup "smoke"
      [ bench "id-noop" $ nf id ()
      ]
  ]
