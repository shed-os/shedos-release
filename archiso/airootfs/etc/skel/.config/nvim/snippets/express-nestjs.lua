-- ═══════════════════════════════════════════════════════════
--            EXPRESS.JS & NESTJS SNIPPETS
-- ═══════════════════════════════════════════════════════════

local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local fmt = require("luasnip.extras.fmt").fmt

return {
  -- Express Router with CRUD endpoints
  s("exrouter", fmt([[
import {{ Router }} from 'express';
import {{ {} }} from '../controllers/{}';

const router = Router();

router.get('/', {}.getAll);
router.get('/:id', {}.getById);
router.post('/', {}.create);
router.put('/:id', {}.update);
router.delete('/:id', {}.delete);

export default router;
]], {
    i(1, "UserController"),
    i(2, "userController"),
    i(3, "userController"),
    i(4, "userController"),
    i(5, "userController"),
    i(6, "userController"),
    i(7, "userController"),
  })),

  -- Express Controller
  s("exctrl", fmt([[
import {{ Request, Response, NextFunction }} from 'express';
import {{ {}Service }} from '../services/{}';

export class {}Controller {{
  private {}Service: {}Service;

  constructor({}Service: {}Service) {{
    this.{}Service = {}Service;
  }}

  getAll = async (req: Request, res: Response, next: NextFunction): Promise<void> => {{
    try {{
      const items = await this.{}Service.findAll();
      res.json(items);
    }} catch (error) {{
      next(error);
    }}
  }};

  getById = async (req: Request, res: Response, next: NextFunction): Promise<void> => {{
    try {{
      const {{ id }} = req.params;
      const item = await this.{}Service.findById(id);

      if (!item) {{
        res.status(404).json({{ message: 'Not found' }});
        return;
      }}

      res.json(item);
    }} catch (error) {{
      next(error);
    }}
  }};

  create = async (req: Request, res: Response, next: NextFunction): Promise<void> => {{
    try {{
      const item = await this.{}Service.create(req.body);
      res.status(201).json(item);
    }} catch (error) {{
      next(error);
    }}
  }};

  update = async (req: Request, res: Response, next: NextFunction): Promise<void> => {{
    try {{
      const {{ id }} = req.params;
      const item = await this.{}Service.update(id, req.body);

      if (!item) {{
        res.status(404).json({{ message: 'Not found' }});
        return;
      }}

      res.json(item);
    }} catch (error) {{
      next(error);
    }}
  }};

  delete = async (req: Request, res: Response, next: NextFunction): Promise<void> => {{
    try {{
      const {{ id }} = req.params;
      await this.{}Service.delete(id);
      res.status(204).send();
    }} catch (error) {{
      next(error);
    }}
  }};
}}
]], {
    i(1, "User"),
    i(2, "userService"),
    i(3, "User"),
    i(4, "user"),
    i(5, "User"),
    i(6, "user"),
    i(7, "User"),
    i(8, "user"),
    i(9, "user"),
    i(10, "user"),
    i(11, "user"),
    i(12, "user"),
    i(13, "user"),
    i(14, "user"),
  })),

  -- Express Middleware
  s("exmw", fmt([[
import {{ Request, Response, NextFunction }} from 'express';

export const {} = (req: Request, res: Response, next: NextFunction): void => {{
  {}
  next();
}};
]], {
    i(1, "middlewareName"),
    i(2, "// Middleware logic"),
  })),

  -- NestJS Controller
  s("nestctrl", fmt([[
import {{ Controller, Get, Post, Put, Delete, Body, Param }} from '@nestjs/common';
import {{ {}Service }} from './{}service';
import {{ {}Dto }} from './dto/{}dto';

@Controller('{}')
export class {}Controller {{
  constructor(private readonly {}Service: {}Service) {{}}

  @Get()
  async findAll(): Promise<{}[]> {{
    return this.{}Service.findAll();
  }}

  @Get(':id')
  async findOne(@Param('id') id: string): Promise<{}> {{
    return this.{}Service.findOne(id);
  }}

  @Post()
  async create(@Body() createDto: {}Dto): Promise<{}> {{
    return this.{}Service.create(createDto);
  }}

  @Put(':id')
  async update(@Param('id') id: string, @Body() updateDto: {}Dto): Promise<{}> {{
    return this.{}Service.update(id, updateDto);
  }}

  @Delete(':id')
  async remove(@Param('id') id: string): Promise<void> {{
    return this.{}Service.remove(id);
  }}
}}
]], {
    i(1, "User"),
    i(2, "user."),
    i(3, "CreateUser"),
    i(4, "create-user."),
    i(5, "users"),
    i(6, "User"),
    i(7, "user"),
    i(8, "User"),
    i(9, "User"),
    i(10, "user"),
    i(11, "User"),
    i(12, "user"),
    i(13, "CreateUser"),
    i(14, "User"),
    i(15, "user"),
    i(16, "UpdateUser"),
    i(17, "User"),
    i(18, "user"),
    i(19, "user"),
  })),

  -- NestJS Service
  s("nestserv", fmt([[
import {{ Injectable, NotFoundException }} from '@nestjs/common';
import {{ InjectRepository }} from '@nestjs/typeorm';
import {{ Repository }} from 'typeorm';
import {{ {} }} from './entities/{}entity';
import {{ {}Dto }} from './dto/{}dto';

@Injectable()
export class {}Service {{
  constructor(
    @InjectRepository({})
    private {}Repository: Repository<{}>,
  ) {{}}

  async findAll(): Promise<{}[]> {{
    return this.{}Repository.find();
  }}

  async findOne(id: string): Promise<{}> {{
    const entity = await this.{}Repository.findOne({{ where: {{ id }} }});
    if (!entity) {{
      throw new NotFoundException(`{} with ID ${{id}} not found`);
    }}
    return entity;
  }}

  async create(createDto: {}Dto): Promise<{}> {{
    const entity = this.{}Repository.create(createDto);
    return this.{}Repository.save(entity);
  }}

  async update(id: string, updateDto: {}Dto): Promise<{}> {{
    await this.{}Repository.update(id, updateDto);
    return this.findOne(id);
  }}

  async remove(id: string): Promise<void> {{
    const result = await this.{}Repository.delete(id);
    if (result.affected === 0) {{
      throw new NotFoundException(`{} with ID ${{id}} not found`);
    }}
  }}
}}
]], {
    i(1, "User"),
    i(2, "user."),
    i(3, "CreateUser"),
    i(4, "create-user."),
    i(5, "User"),
    i(6, "User"),
    i(7, "user"),
    i(8, "User"),
    i(9, "User"),
    i(10, "user"),
    i(11, "User"),
    i(12, "user"),
    i(13, "User"),
    i(14, "CreateUser"),
    i(15, "User"),
    i(16, "user"),
    i(17, "user"),
    i(18, "UpdateUser"),
    i(19, "User"),
    i(20, "user"),
    i(21, "user"),
    i(22, "User"),
  })),

  -- NestJS Module
  s("nestmod", fmt([[
import {{ Module }} from '@nestjs/common';
import {{ TypeOrmModule }} from '@nestjs/typeorm';
import {{ {}Controller }} from './{}controller';
import {{ {}Service }} from './{}service';
import {{ {} }} from './entities/{}entity';

@Module({{
  imports: [TypeOrmModule.forFeature([{}])],
  controllers: [{}Controller],
  providers: [{}Service],
  exports: [{}Service],
}})
export class {}Module {{}}
]], {
    i(1, "User"),
    i(2, "user."),
    i(3, "User"),
    i(4, "user."),
    i(5, "User"),
    i(6, "user."),
    i(7, "User"),
    i(8, "User"),
    i(9, "User"),
    i(10, "User"),
    i(11, "User"),
  })),

  -- NestJS DTO
  s("nestdto", fmt([[
import {{ IsString, IsNotEmpty, IsOptional, IsEmail, MinLength }} from 'class-validator';

export class {}Dto {{
  @IsString()
  @IsNotEmpty()
  {}: string;

  @IsEmail()
  @IsNotEmpty()
  email: string;

  {}
}}
]], {
    i(1, "CreateUser"),
    i(2, "name"),
    i(3, "// Additional fields"),
  })),

  -- NestJS Entity (TypeORM)
  s("nestent", fmt([[
import {{ Entity, Column, PrimaryGeneratedColumn, CreateDateColumn, UpdateDateColumn }} from 'typeorm';

@Entity('{}')
export class {} {{
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({{ unique: true }})
  {}: string;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;

  {}
}}
]], {
    i(1, "users"),
    i(2, "User"),
    i(3, "email"),
    i(4, "// Additional columns"),
  })),
}
