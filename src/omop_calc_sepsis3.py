
from omop_calc_sofa import baseline_sofa
def sepsis3_events(sofa_hourly, infection_times):
    events=[]
    for inf in infection_times:
        base = baseline_sofa(sofa_hourly, inf)
        # find first time delta >=2 within 48h
        for row in sofa_hourly:
            if inf <= row['t'] <= inf + pd.Timedelta(hours=48):
                if row['total'] - base >= 2:
                    events.append({'infection_time':inf,'sofa_time':row['t'],'delta':row['total']-base,'baseline':base})
                    break
    return events
