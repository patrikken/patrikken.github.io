---
title: "The hidden ensemble inside tabular foundation models"
date: 2026-10-15
description: "Tabular foundation models quietly average over perturbed copies of your table. I opened two of them up to see what that buys. A lot of Elo, very little accuracy."
tags: [tabular, foundation-models, ensembling, tabarena]
---

# The hidden ensemble inside tabular foundation models

Tabular foundation models (TFMs) look like they make one forward pass: you give them a training table and a few query rows, and they predict. In practice they don't. TabICLv2, TabFM, TabPFN and Mitra each run the model several times on perturbed copies of your table and average the answers. The perturbations are things like shuffling the columns, shuffling the class labels, or changing the preprocessing.

This ensemble ships as a default and is rarely ablated. I wanted to know what it actually does, so I opened up the two strongest open models I could instrument, TabICLv2 and TabFM, and ran them on all 51 TabArena datasets (30 binary, 8 multiclass, 13 regression). The short version: the ensemble helps reliably, the gain is tiny, and the leaderboard scale we use to report it makes it look much bigger than it is.

*This is a light write-up of a paper in progress. The full version has the tables, tests and caveats: [link to paper].*

## What I did

I modified the inference loop of each model so that every ensemble member's prediction is cached. After that, the number of members, which perturbations are included and how members are averaged are all cheap post-hoc operations. About 48,000 cached cells later, I could ask questions that would otherwise cost a GPU run each.

I use two scales throughout:

- **Elo**, computed the way TabArena does it (pairwise wins across datasets and splits). Mine is *local*: it comes from a pool of my own configurations, not the official leaderboard pool.
- **Effect size** in the task's own metric: AUC for binary, log-likelihood for multiclass, relative RMSE reduction for regression, with a paired Wilcoxon test over datasets.

## 1. The ensemble earns a lot of Elo for very little accuracy

Against a single forward pass, the shipped ensembles earn between 168 and 230 Elo. In the task's own metric, that is:

| Task | Gain from the shipped ensemble |
|---|---|
| Binary | about 0.001 AUC (0.0012 for TabICLv2, 0.0014 for TabFM) |
| Multiclass | 0.002 to 0.003 log-likelihood |
| Regression | 0.7% to 0.9% lower RMSE |

The gain is real and consistent. TabFM's ensemble beats a single pass on 27 of 30 binary datasets, and on all 13 regression datasets. But a thousandth of AUC is a thousandth of AUC.

![Elo gain against effect size for every configuration I ran. Left to right: binary, multiclass, regression.](img/fig_gap.png)

*Figure 1. Local Elo gain against effect size, for every configuration of both models I ran. Colour is the model. Circles (native) are ensembles built from column order, class order and preprocessing, squares (A4) give each member only some of the columns, and triangles (A5) give each member only some of the rows. The horizontal axes are symmetric-log.*

Figure 1 puts every configuration on both scales. They all fall on one monotone curve, and it is steep. A method that wins by a small margin on most datasets earns a large Elo. Elo tells you the ensemble helps *consistently*. It does not tell you how much. I would read it as a statement about consistency and report an effect size next to it.

One caveat: my Elo pool contains many near-copies of each other, which probably amplifies the effect. I haven't computed Elo against the official TabArena pool yet, and I expect the curve to be flatter there.

## 2. The 32 members are almost one member

The shipped ensembles average 32 members (fewer for TabICLv2 on some tasks). I measured how many *independent* predictions that is, using the participation ratio of the members' error correlation. The median pool carries between 1.0 and 1.2 effective members.

So the members are close to copies of each other. Perturbing the input of a frozen network barely changes what it believes. That fits the size of the gains above.

Most of the gain also arrives early. For TabFM, 8 members reach 78% to 84% of the 32-member gain, and 16 members reach 89% to 94%. A single perturbed member is actually *worse* than the unperturbed pass, so the ensemble first has to recover its own damage.

![Elo gain as the number of members grows.](img/fig_elo_vs_M.png)

*Figure 2. Local Elo gain over a single pass as the number of members grows. A1 is column order, A2 is class order, A3 is preprocessing, and the others are combinations; "shipped" is the model's default mix. Top row: TabICLv2. Bottom row: TabFM. Left to right: binary, multiclass, regression. Shaded bands are 95% bootstrap CIs.*

## 3. Column order, class order and preprocessing explain the gain

The shipped recipes mix three perturbations: column order, class order and preprocessing. I decomposed the gain over them with Shapley values, and I also tried the full product of all three instead of the shipped mix.

On binary and regression tasks, the full product is no better than the shipped mix. The only possible exception is multiclass TabICLv2 (+0.003 log-likelihood, improving 7 of 8 datasets), but with 8 datasets the test gives p = 0.078, so I don't count it as established. Which axis matters most depends on the model and the task: preprocessing carries about half the multiclass gain for TabICLv2, while class order matters most for TabFM. I wouldn't expect that ordering to transfer.

## 4. Giving each member less of the table never helps

Another family of tricks gives each member only part of the table: a random subset of columns, or a random subset of rows. The hope is diversity. I tested these on top of the shipped recipe:

- **Keep half of the columns:** −0.0045 AUC (TabICLv2) and −0.0048 (TabFM) on binary tasks, p < 0.001.
- **Keep half of the rows:** −0.0025 and −0.0022 AUC, p < 0.001.
- **Keep 90%:** neutral on classification. On regression, keeping 90% of the rows still makes RMSE slightly worse (0.4% for TabICLv2, 0.3% for TabFM, p < 0.01).

I did not find a setting where withholding information beats the shipped recipe.

### But what about round-robin subsampling?

Some wrappers deal columns out round-robin, with the argument that every column is then seen by some member. That sounds like it should fix the information loss, so I tested it directly against random draws at the same budget (TabICLv2, 16 members, half the columns each).

It doesn't. Round-robin gains +0.0007 AUC over random draws (p = 0.16), which is within noise, and it stays 0.0028 AUC *below* a single full-table pass. The reason is that coverage was never the problem: with 16 members and half the columns each, the chance that a given column is missed by every member is about 1.5 in 100,000. What hurts is what each member *cannot see*, not which columns the ensemble misses.

Coverage only starts to matter when members keep almost everything. On binary tasks, leave-one-fold-out partitions that drop 12.5% of the columns per member match the shipped ensemble within noise. I only ran these designs for TabICLv2 at half the columns, so treat the round-robin result as specific to that setting.

## 5. Two additions that behave differently

- **Relabelling categorical codes per member** is a good example of the Elo gap. For TabICLv2 it earns +92 Elo on binary tasks, and the effect size is 0.0004 AUC with p = 0.15. A decent rating, and nothing measurable behind it.
- **Appending extra features (SVD projections, crosses) to TabFM** does help on multiclass and regression tasks: +0.0010 log-likelihood on all 8 multiclass datasets (p = 0.008) and a 0.5% RMSE reduction on regression (p = 0.021). On binary tasks it does nothing. I don't know why binary differs.

Aggregation also matters. TabFM's extended configuration adds feature expansion, probability pooling and calibration. On multiclass tasks most of its gain comes from the pooling and calibration, not from the members.

## What I'd take away

1. The ensemble inside a TFM is a small, reliable variance-reduction step, not a source of new information.
2. Report an effect size and a paired test next to Elo when you compare ensemble variants. Elo alone reports consistency.
3. If you are tempted to add subsampling-based diversity, the evidence here says it costs more than it gives. Extra features and better aggregation look more promising.

## Caveats

- All Elo values are local. Official-pool Elo is still to come.
- Two models only, and their rankings of the perturbation axes differ, so I'm not claiming anything at the level of "all TFMs".
- Multiclass has 8 datasets and regression 13, so several conclusions sit near p = 0.05 to 0.08. Some regression means are driven by a few datasets.
- TabFM is missing splits on five large classification datasets, and about 60% of my splits differ in size from TabArena's recorded ones. I log the mismatch and do not filter.
- The extra perturbations (subsampling, relabelling, expansion) are interventions I added. They show what the wrappers *could* do, not what the released ones do.

The harness and the member cache will be released with the paper: [link to code].
