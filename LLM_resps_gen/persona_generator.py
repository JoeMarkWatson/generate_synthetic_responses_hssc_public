import random
import json
import numpy as np
from scipy.stats import truncnorm
from io_utils import read_txt_config

def parse_theta_distribution(path):
    lines = read_txt_config(path).splitlines()
    config = {}
    for line in lines:
        if ':' in line:
            key, val = [s.strip() for s in line.split(':', 1)]
            if key == "theta_bounds":
                try:
                    config[key] = json.loads(val)
                except:
                    config[key] = [float(v) for v in val.strip('[]').split(',')]
            elif key in {"theta_mean", "theta_sd"}:
                config[key] = float(val)
            elif key == "n":
                config[key] = int(val)
            else:
                config[key] = val
    return config

def sample_thetas(n, mean, sd, bounds):
    a, b = (bounds[0] - mean) / sd, (bounds[1] - mean) / sd
    return truncnorm.rvs(a, b, loc=mean, scale=sd, size=n)


def _sample_numeric_from_config(conf):
    min_val = int(conf["min"])
    max_val = int(conf["max"])
    if min_val > max_val:
        raise ValueError(f"numeric_distribution min must be <= max; got {min_val}, {max_val}")

    distribution = conf["distribution"]
    if distribution == "uniform":
        return random.randint(min_val, max_val)

    if distribution == "right_skewed":
        # Approximate bounded right-skew via beta distribution on [min, max].
        # Higher skewness increases mass near the lower bound.
        skewness = float(conf.get("skewness", 1.0))
        if skewness <= 0:
            raise ValueError(
                "right_skewed requires a positive 'skewness' value in synth_sample_config."
            )

        alpha = max(0.5, 2.0 - 0.5 * skewness)
        beta = alpha + 1.0 + skewness
        draw = np.random.beta(alpha, beta)
        value = min_val + draw * (max_val - min_val)
        return int(round(value))

    raise NotImplementedError(f"Unsupported distribution: {distribution}")

def percentile_label(p):
    if p < 10:
        return "extremely low"
    elif p < 25:
        return "low"
    elif p < 40:
        return "below average"
    elif p < 60:
        return "average"
    elif p < 75:
        return "above average"
    elif p < 90:
        return "high"
    else:
        return "extremely high"

def _normalize_gender(value):
    if not isinstance(value, str):
        return value
    token = value.strip().lower()
    if token in {"m", "male"}:
        return "M"
    if token in {"f", "female"}:
        return "F"
    return value


def _sample_demographics(demogs):
    sampled = {}
    for key, conf in demogs.items():
        if conf["type"] == "categorical":
            options = list(conf["distribution"].keys())
            weights = [float(v.strip('%')) for v in conf["distribution"].values()]
            sampled[key] = random.choices(options, weights=weights)[0]
        elif conf["type"] == "numeric_distribution":
            sampled[key] = _sample_numeric_from_config(conf)
        else:
            raise ValueError(f"Unknown demographic type for {key}")
    if "gender" in sampled:
        sampled["gender"] = _normalize_gender(sampled["gender"])
    return sampled


def generate_base_personas_from_rows(n, demographic_rows):
    if not demographic_rows:
        raise ValueError("demographic_rows must not be empty")

    personas = []
    for i in range(n):
        sampled = dict(random.choice(demographic_rows))
        p = {
            "persona_id": f"p{i+1}",
            **sampled,
        }
        personas.append(p)
    return personas


def generate_base_personas(n, demogs):
    personas = []
    for i in range(n):
        p = {
            "persona_id": f"p{i+1}",
        }
        p.update(_sample_demographics(demogs))
        personas.append(p)
    return personas


def generate_trait_percentiles(n, theta_conf):
    thetas = sample_thetas(
        n,
        theta_conf['mean'],
        theta_conf['sd'],
        theta_conf['bounds']
    )
    rows = []
    for i in range(n):
        theta = float(thetas[i])
        percentile = round(100 * truncnorm.cdf(
            theta,
            (theta_conf['bounds'][0] - theta_conf['mean']) / theta_conf['sd'],
            (theta_conf['bounds'][1] - theta_conf['mean']) / theta_conf['sd'],
            loc=theta_conf['mean'], scale=theta_conf['sd']
        ))
        percentile = max(1, min(99, int(percentile)))
        rows.append({
            "persona_id": f"p{i+1}",
            "trait_percentile": percentile,
        })
    return rows


def generate_personas(n, theta_conf, trait_name, demogs):
    base_personas = generate_base_personas(n, demogs)
    trait_rows = generate_trait_percentiles(n, theta_conf)
    personas = []
    for base, trait in zip(base_personas, trait_rows):
        percentile = int(trait["trait_percentile"])
        label = percentile_label(percentile)
        p = {
            **base,
            "theta_description": f"A level of '{trait_name}' higher than {percentile}% of the population ({label}).",
            "trait_percentile": percentile,
        }
        personas.append(p)
    return personas
