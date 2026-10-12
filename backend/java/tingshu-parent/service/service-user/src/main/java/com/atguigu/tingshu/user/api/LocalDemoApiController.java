package com.atguigu.tingshu.user.api;

import com.atguigu.tingshu.common.constant.RedisConstant;
import com.atguigu.tingshu.common.result.Result;
import com.atguigu.tingshu.model.user.UserListenProcess;
import com.atguigu.tingshu.user.service.UserInfoService;
import com.atguigu.tingshu.vo.user.UserInfoVo;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.web.bind.annotation.*;
import java.math.BigDecimal;
import java.util.*;
import java.util.concurrent.TimeUnit;

/** 本地演示账号入口：必须同时启用 local profile 和显式开关。 */
@Profile("local")
@ConditionalOnProperty(name="listening.demo-login-enabled", havingValue="true")
@RestController
@RequestMapping("/api/user/local")
public class LocalDemoApiController {
    private final UserInfoService users;
    private final RedisTemplate<Object, Object> redis;
    private final MongoTemplate mongo;

    public LocalDemoApiController(UserInfoService users, RedisTemplate<Object, Object> redis, MongoTemplate mongo) {
        this.users = users;
        this.redis = redis;
        this.mongo = mongo;
    }

    @PostMapping("/login")
    public Result<Map<String, Object>> login() {
        UserInfoVo user = users.getUserInfoVo(900001L);
        if (user == null) throw new IllegalStateException("请先导入本地演示 SQL");
        String token = UUID.randomUUID().toString();
        redis.opsForValue().set(RedisConstant.USER_LOGIN_KEY_PREFIX + token, user, 1, TimeUnit.HOURS);
        // 仅第一次创建示例收听记录，重复登录不覆盖真实测试进度。
        if (!mongo.exists(org.springframework.data.mongodb.core.query.Query.query(
                org.springframework.data.mongodb.core.query.Criteria.where("_id").is("local-demo-progress")),
                "userListenProcess_900001")) {
            UserListenProcess progress = new UserListenProcess();
            progress.setId("local-demo-progress");
            progress.setUserId(900001L);
            progress.setAlbumId(900001L);
            progress.setTrackId(900001L);
            progress.setBreakSecond(new BigDecimal("125"));
            progress.setIsShow(1);
            progress.setCreateTime(new Date());
            progress.setUpdateTime(new Date());
            mongo.save(progress, "userListenProcess_900001");
        }
        return Result.ok(Map.of("token", token, "nickname", user.getNickname(), "demo", true));
    }
}
