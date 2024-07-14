# Apex
### **Protect your Liquidity 🔒**


## Set up

*requires [foundry](https://book.getfoundry.sh)*

```
forge install
forge test
```


We enable prediction markets to use AMMs by protecting LPs from severe IL and LVR costs. This eliminates the key barrier that currently forces prediction markets to rely on order books.



## Current Challenges

Prediction markets face unique liquidity challenges due to their volatile nature and binary outcomes. Unlike traditional markets, prediction market shares often end up worth $0 if their outcome isn't realized, exposing liquidity providers (LPs) to significant impermanent loss (IL). This makes liquidity provision less attractive compared to other markets.

As a result, popular prediction market protocols like Polymarket are forced to rely on orderbooks instead of Automated Market Makers (AMMs), as standard AMMs are unsuitable for these challenges. This approach requires active management from LPs, ruling out non-custodial passive liquidity provision that is popular for other ERC20 tokens.

Consequently, even the most popular Polymarket prediction markets often have very low depth despite having hundreds of millions in Total Value Locked (TVL). This degrades the trading experience for users due to unnecessary price impact.

#### Our Solution: Custom v4 AMM Hooks

We address these challenges by developing a suite of custom v4 AMM hooks, each designed to mitigate either Impermanent Loss (IL) or Loss Versus Rebalancing (LVR) using novel techniques and heuristics.

##### 1. Addressing Loss Versus Rebalancing (LVR)

LVR refers to the loss LPs incur due to getting "bad execution" or sub-optimal trade prices from arbitrageurs or traders using the AMM. This results from AMMs often being "too eager to trade" at unfavorable prices for LPs.

Example: An AMM continues to offer "yes" shares for the winning candidate in an election market for 70 cents, for several minutes after the candidate is announced as the winner (when they are worth one dollar). In this scenario, LPs unnecessarily accept less than $1 for shares, losing out on valuable income.

###### Solution: Post-Trade English Auction Hook

Our first hook initiates a simple English auction after every trade, offering a time window for other traders to offer LPs a superior price. This saves LPs from poor execution due to arbitrageurs exploiting newly available information.

In the context of the above example:
- Instead of selling to the first trader who offered 70 cents for their $1 shares, LPs would receive much closer to one dollar.
- Other traders would bid up to that amount during the auction window following the original 70-cent trade.

This mechanism prevents LPs from falling victim to toxic/informed traders without relying on external oracles or other trusted third parties. It uses a simple auction mechanism and a small waiting period as a form of market oracle.

Future Improvement: We plan to trigger auctions only when volatility within the last n minutes is above a threshold, including the price impact of the current trade. This way, most trades settle instantly, except those in very high volatility conditions where the risk of poor execution is highest for LPs.

##### 2. Mitigating Rebalancing Loss

Rebalancing loss, similar to impermanent loss, is caused by the prices of assets in the pair diverging. AMMs automatically rebalance into the asset that declines in value, potentially selling almost 100% of the other asset if one asset in the pair goes to zero. This is common in prediction markets, as shares become worth $0 if the corresponding event doesn't occur. Dynamic fees alone are insufficient to mitigate rebalancing loss, because they do not prevent the LP portfolio from rebalancing into the depreciating shares, especially those which fall to $0.

###### Solution: Dynamic Liquidity Adjustment Hook

Our second hook gradually decreases the prediction market's liquidity when volatility is expected to increase. This reduces LPs' exposure and resulting losses from IL that comes with heightened liquidity. The strategy is to "pull out" liquidity automatically on LPs' behalf to protect them from risky market conditions.

We use two heuristics to predict heightened volatility:
1. Time to market resolution date: Volatility generally increases as the resolution date approaches due to more information becoming known.
2. Deviation from starting price: Volatility typically increases as prediction market share prices diverge from their starting price, indicating new information has become available. This heuristic is useful when important information causing volatility becomes known well before the resolution date.

### Conclusion

We believe specialist LPs already implement similar strategies in prediction market orderbooks (see: https://pub.tik.ee.ethz.ch/students/2022-HS/SA-2022-42.pdf). Our goal is to bring these sophisticated strategies to non-specialist passive liquidity providers, making liquidity provision in prediction markets less risky and more accessible. This approach aims to create deeper, more efficient prediction markets without sacrificing LP protection.



### Implementation Details

We dynamically adjust liquidity with V4 hooks by scaling up the trade size in the beforeSwap hook, then scaling it back down in the afterSwap hook. This makes the swap() function believe the trade is larger than it really is, without impacting the tokens sent or received by the trader (except due to higher price impact of the larger trade).

This approach allows us to:
- Cause trades to consume more tick liquidity than they otherwise would.
- Deactivate a variable fraction of tick liquidity by making it inaccessible to traders.
- Vary liquidity availability over time in response to our volatility heuristics.

The fraction of liquidity made inaccessible to traders is proportional to the coefficient by which we scale their trades.

In order to do this, we needed to also account for LP balances changing less than what swap() would expect, due to the actual trade size being smaller than what it sees. We do this via a _afterRemoveLiquidity and _afterRemoveLiquidity hook, which we use to keep track of the delta between actual LP balances and stored LP balances, via a global accumulator and an accumulator checkpoint stored for each LP.

We have also implemented forge tests to verify our hook contract is functioning as expected.

The auction mechanism for the LVR-mitigation hook works by keeping track of the highest bidder so far in the auction-window, and refunding the last highest bidder their bid amount as soon as they are out-bid. This way, it is capital efficient, simple and doesn't impose additional delays on or create ambiguity for traders as other auctions such as second-price or blind auctions would.

All tests can be executed with the command `forge test`