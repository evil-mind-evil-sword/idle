# Self-Bias in Large Language Models and Agents

LLMs systematically favor their own outputs. This bias corrupts evaluation, amplifies through training loops, and poses distinct risks for agentic systems. This report synthesizes quantitative findings from 2024-2025 research and provides actionable recommendations.

## Executive Summary

**Core finding:** LLMs rate their own outputs approximately 4-10% higher than human evaluators do, even when output quality is equivalent [Arize AI, 2025†]. This self-preference bias correlates with a proposed mechanism: LLMs prefer low-perplexity (familiar) text regardless of its source [Wataoka et al., 2024].

**Key numbers:**
- GPT-4 self-recognition accuracy: 73.5% [Panickssery et al., 2024]
- GPT-4 self-preference bias score: 0.520 on a -1 to +1 scale where 0 is neutral [Wataoka et al., 2024]
- OpenAI self-evaluation inflation: +9.4% [95% CI: 7.4-11.3] [Arize AI, 2025†]
- Anthropic self-evaluation inflation: +4.27% [95% CI: 3.6-5.0] [Arize AI, 2025†]
- Preference leakage via SFT: 23.6% vs DPO: 5.2% [Li et al., 2025]

†Non-peer-reviewed source; treat with appropriate caution.

**Implications for idle:** Multi-model review (alice as external reviewer) directly mitigates self-preference bias. Cross-model architectures reduce the risk of echo chambers and inflated quality assessments.

## Definitions and Taxonomy

This report uses "self-bias" as an umbrella term for several distinct but related phenomena: self-recognition, self-preference, self-evaluation inflation, and preference leakage. These may share underlying mechanisms (perplexity-based familiarity preference) but have been studied separately with different methodologies. Caution is warranted when comparing metrics across studies.

### Self-Preference Bias

An LLM evaluator scores its own outputs higher than alternatives, while human annotators consider them of equal quality. Formally defined by Wataoka et al. (2024):

```
Bias = P(Y'=1|S=1,Y=1) − P(Y'=1|S=0,Y=1)
```

Where:
- `Y` = human-preferred response index
- `Y'` = LLM evaluator's preferred response index
- `S` = indicator that LLM evaluator generated the response

The metric ranges from -1 to +1, with 0 indicating no bias.

### Self-Recognition

The ability of an LLM to distinguish its own outputs from those of other models or humans. Research shows self-recognition correlates linearly with self-preference strength (Panickssery et al., 2024).

### Preference Leakage

Contamination in LLM-as-a-judge systems caused by relatedness between data generators and evaluators. Three types of relatedness:
1. **Same model** - Generator and judge are identical
2. **Inheritance** - Judge trained on generator's outputs
3. **Same family** - Generator and judge share architectural lineage

### Related Biases

| Bias | Description | Measured Effect |
|------|-------------|-----------------|
| Position bias | Prefer responses in specific positions | GPT-3.5: 50%, Claude-v1: 70% first-position preference |
| Verbosity bias | Prefer longer responses | Variable by model |
| Ordering bias | Preference reversal based on presentation order | GPT-4: 25%, Llama 2: 89% |

## Quantitative Evidence

### Self-Recognition Accuracy

Panickssery et al. (2024) measured out-of-box self-recognition in pairwise settings:

| Model | Self-Recognition Accuracy | Baseline |
|-------|---------------------------|----------|
| GPT-4 | 73.5% | 50% |
| GPT-3.5 | 53.5% | 50% |
| Llama 2 | 51.4% | 50% |

After supervised fine-tuning on 500 examples:
- GPT-3.5: >90% accuracy
- Llama 2: >90% accuracy

### Self-Preference Scores

Self-preference measured in pairwise evaluation settings (Panickssery et al., 2024):

| Model | XSUM Dataset | CNN/DailyMail |
|-------|--------------|---------------|
| GPT-4 | 0.705 | 0.912 |
| GPT-3.5 | 0.582 | 0.431 |
| Llama 2 | 0.511 | 0.505 |

Human annotators rated self-generated summaries as equal quality to alternatives—the preference differential is pure bias.

### Bias Scores by Model

Wataoka et al. (2024) evaluated 33,000 dialogues from Chatbot Arena. Scores range from -1 to +1, with 0 indicating no bias:

| Model | Bias Score | Interpretation |
|-------|------------|----------------|
| GPT-4 | 0.520 | Strong positive bias |
| Vicuna-13b | High | Strong positive bias |
| GPT-3.5-Turbo | Lower | Moderate positive bias |
| Vicuna-7b | ~0 | Near neutral |
| oasst-pythia-12b | Negative | Reverse bias (prefers others) |

Models with negative bias (reverse self-preference) exist, indicating this phenomenon is not universal.

### Self-Recognition / Self-Preference Correlation

Fine-tuning for self-recognition produces linear correlation with self-preference (Kendall's τ):

| Model | Dataset | No Fine-tuning | 500 Examples |
|-------|---------|----------------|--------------|
| GPT-3.5 | XSUM | 0.41 | 0.74 |
| Llama 2 | XSUM | 0.73 | — |

This correlation suggests a causal mechanism: improving self-recognition amplifies self-preference.

### Real-World Evaluation Bias

Arize AI (2025) tested four model families as both agents and evaluators:

| Evaluator | Self-Score | Baseline Avg | Delta | 95% CI |
|-----------|-----------|--------------|-------|--------|
| OpenAI (GPT-4.1) | 65% | 55.6% | +9.4% | [7.4, 11.3] |
| Anthropic (Claude 3.7) | 82.3% | 78.03% | +4.27% | [3.6, 5.0] |
| Google (Gemini 2.5) | 72.5% | 66.4% | +6.1% | [2.9, 9.2] |
| Qwen | 70.6% | 65.9% | +4.7% | [2.9, 7.0] |

All confidence intervals exclude zero—self-bias is statistically significant across all major model families. Anthropic showed the smallest and most stable bias.

### Preference Leakage by Training Method

Li et al. (2025) measured preference leakage across learning methods:

| Method | Average Leakage Score |
|--------|----------------------|
| SFT (Supervised Fine-Tuning) | 23.6% |
| DPO (Direct Preference Optimization) | 5.2% |

DPO's pairwise optimization reduces memorization of sensitive training characteristics.

## Proposed Mechanisms

### The Perplexity Hypothesis

Wataoka et al. (2024) identified the core mechanism: **LLMs assign higher evaluations to texts with lower perplexity regardless of whether the texts were self-generated.**

```
Self-generated text → Lower perplexity for same model → Higher evaluation score
```

This may explain why self-preference exists: LLMs prefer familiar text, and their own outputs are maximally familiar. If confirmed, this suggests the bias is not about identity recognition but about distributional similarity.

Supporting evidence:
1. LLMs favor low-perplexity text even from other sources
2. The effect persists when models cannot identify their own outputs
3. Perplexity correlates with evaluation scores across all tested models

### Self-Recognition as Amplifier

Panickssery et al. (2024) demonstrated that self-recognition capability amplifies self-preference:

```
Increased self-recognition → Stronger self-preference bias
```

Fine-tuning for self-recognition (without explicit preference training) increases self-preference. This suggests the representations are entangled.

### Style Artifacts in Synthetic Data

Preference leakage research (Li et al., 2025) found that models trained on synthetic data inherit style and format characteristics from the generator. A fine-tuned BERT classifier achieved high accuracy distinguishing responses by source model, indicating detectable stylistic fingerprints.

## Mitigation Strategies

### 1. Multi-Model Ensemble Evaluation

Using multiple models as judges reduces individual biases. Wataoka et al. (2024) propose perplexity-weighted ensembles:

```
When a model shows low perplexity on a sample:
  → Decrease that model's evaluation weight for that sample
```

**Effectiveness:** Reduces systematic bias by averaging across different preference profiles.

**Limitation:** Increases cost and latency.

### 2. Blind Evaluation Protocols

Hide model identity from evaluators. Research shows label-induced bias distorts outcomes when evaluators know the source model.

**Effectiveness:** Reduces conscious preference adjustments.

**Limitation:** Does not address perplexity-based preference.

### 3. Activation Steering

"Breaking the Mirror" (Roytburg et al., 2025) applied steering vectors to reduce self-preference:

**Effectiveness:** Up to 97% reduction in biased cases.

**Critical limitation:** "Representational entanglement" causes instability on legitimate evaluations. The bias representation overlaps with core evaluation capability.

### 4. DPO Over SFT for Training

DPO achieves 5.2% preference leakage vs SFT's 23.6%. Pairwise optimization reduces memorization of style artifacts.

**Effectiveness:** 4.5x reduction in preference leakage.

**Limitation:** Does not eliminate self-bias, only reduces inheritance effects.

### 5. Cross-Family Evaluation

Use evaluators from different model families than generators. Same-family bias is stronger than cross-family bias.

**Effectiveness:** Reduces family-specific preference patterns.

**Limitation:** May introduce different systematic biases.

## Implications for Agentic Systems

### Self-Improvement Loops

Agents that evaluate their own outputs for iterative improvement risk runaway bias amplification:

```
Agent generates → Agent evaluates → Agent selects "best" → Agent trains
        ↑                                                        |
        └────────────── Bias compounds each iteration ───────────┘
```

Research on feedback loops (ICML 2024) identifies two harmful processes:
1. **Output-refinement** - Agent makes outputs more like its preferred style
2. **Policy-refinement** - Agent updates preferences toward its own outputs

### Multi-Agent Groupthink

Multi-agent systems risk convergence to suboptimal solutions when:
- Agents from the same family evaluate each other
- Dominant agent opinions sway consensus
- Independent reasoning is not enforced

Studies find LLM judges favor arguments from same-family agents, biasing debate outcomes.

### Memory-Enhanced Agent Bias

Agents with persistent memory amplify bias over time:
1. Memory draws on biased data
2. Reflection processes entrench biases through skewed feedback
3. Personalization introduces and compounds preference drift

Research demonstrates existing guardrails are insufficient for agentic settings.

### RLAIF Propagation

Reinforcement Learning from AI Feedback propagates critic model biases:

```
Flawed critic → Biased rewards → Reinforced bad behaviors
```

Relying on AI critics means any flaws are propagated and reinforced during training.

## Recommendations for Multi-Model Architectures

### For idle and Similar Systems

1. **Use external reviewers from different model families.** Alice (opus-based) reviewing sonnet outputs directly mitigates within-family bias.

2. **Implement blind review.** Do not expose model identity in review prompts.

3. **Weight by disagreement.** When multiple reviewers agree despite different family biases, confidence should increase.

4. **Monitor for groupthink.** Track convergence patterns; inject diversity when reviewers consistently agree.

### For Evaluation Pipelines

1. **Never use self-evaluation for quality gates.** Use cross-model evaluation or human review.

2. **Calibrate against human baselines.** The Arize study found that calibration eliminates apparent bias in some cases.

3. **Report confidence intervals.** Self-bias magnitude varies; statistical significance testing catches spurious preferences.

### For Training Pipelines

1. **Prefer DPO over SFT** when training on synthetic data. 4.5x reduction in preference leakage.

2. **Diversify synthetic data sources.** Mix generators from different families.

3. **Monitor perplexity distributions.** Flag when training data has unusually low perplexity for the target model.

## Open Questions

1. **Is bias eliminable?** Activation steering achieves 97% reduction but destabilizes legitimate evaluation. The bias may be fundamentally entangled with evaluation capability.

2. **Does scaling help?** Current evidence shows larger models (GPT-4) have stronger self-recognition and stronger bias. Scaling may exacerbate rather than resolve the problem.

3. **Cross-modal transfer?** Self-bias is studied primarily in text. Whether vision-language models exhibit analogous bias in image evaluation is underexplored.

4. **Optimal ensemble size?** Diminishing returns likely exist for multi-model ensembles. The cost-benefit tradeoff is not characterized.

## Bibliography

### Primary Sources

1. Wataoka, K., Takahashi, T., & Ri, R. (2024). Self-Preference Bias in LLM-as-a-Judge. *NeurIPS 2024 Safe Generative AI Workshop*. https://arxiv.org/abs/2410.21819

2. Panickssery, A., Bowman, S. R., & Feng, S. (2024). LLM Evaluators Recognize and Favor Their Own Generations. *NeurIPS 2024*. https://arxiv.org/abs/2404.13076

3. Li, D., et al. (2025). Preference Leakage: A Contamination Problem in LLM-as-a-judge. https://arxiv.org/abs/2502.01534

4. Roytburg, D., Bozoukov, M., Fu, H., Nguyen, M., Barzdukas, J., & Oozeer, N. F. (2025). Breaking the Mirror: Examining Self-Preference in LLM Evaluators through Activation-Based Representations. *NeurIPS 2025 Workshop on Evaluating the Evolving LLM Lifecycle*. https://openreview.net/forum?id=q82Pqka5sb

### Secondary Sources

5. Arize AI. (2025). Should I Use the Same LLM for My Eval as My Agent? Testing Self-Evaluation Bias. https://arize.com/blog/should-i-use-the-same-llm-for-my-eval-as-my-agent-testing-self-evaluation-bias/ (Non-peer-reviewed industry blog.)

6. Gallegos, I., et al. (2024). Bias and Fairness in Large Language Models: A Survey. *Computational Linguistics*, 50(3). https://direct.mit.edu/coli/article/50/3/1097/121961/

7. Pan, A., Jones, E., Jagadeesan, M., & Steinhardt, J. (2024). Feedback loops with language models drive in-context reward hacking. *ICML 2024*. https://arxiv.org/abs/2402.06627

8. Anthropic. (2025). Emergent Introspective Awareness in Large Language Models. https://www.anthropic.com/research/introspection

9. Anthropic. (2025). Agentic Misalignment: How LLMs could be insider threats. https://www.anthropic.com/research/agentic-misalignment

### Background

10. Bai, Y., et al. (2022). Constitutional AI: Harmlessness from AI Feedback. https://arxiv.org/abs/2212.08073

11. Turner, A., et al. (2023). Activation Addition: Steering Language Models Without Optimization. https://arxiv.org/abs/2308.10248

---

*Last updated: December 2025*
*Research confidence: HIGH*
*Status: COMPLETE*
